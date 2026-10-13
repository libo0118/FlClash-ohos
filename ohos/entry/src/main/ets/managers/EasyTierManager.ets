import { vpnExtension } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import easyTier from 'easytier-ohrs'
import { EasyTierProps } from '../models/State'

const INSTANCE_ID = '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0'
const SOCKS_PORT = 17890
const MAX_RUNTIME_JSON_LENGTH = 2 * 1024 * 1024
const MAX_ROUTE_CANDIDATES = 4096

export type EasyTierRouteStatus = 'starting' | 'ready' | 'stopped'

export interface EasyTierRouteSnapshot {
  sessionId: string
  configTag: string
  revision: number
  status: EasyTierRouteStatus
  cidrs: string[]
}

export function sanitizeStartupMessage(message: string, networkSecret: string): string {
  if (!networkSecret) return message
  const escapedSecret = JSON.stringify(networkSecret).slice(1, -1)
  return message.split(escapedSecret).join('[已隐藏]').split(networkSecret).join('[已隐藏]')
}

export function startupErrorMessage(stage: string, error: Error, networkSecret: string): string {
  const code = (error as BusinessError)?.code
  const codeText = typeof code === 'number' ? `（错误码 ${code}）` : ''
  return sanitizeStartupMessage(`${stage}${codeText}: ${error?.message ?? '未知错误'}`, networkSecret).slice(0, 2400)
}

class EmbeddedNetworkConfig {
  instance_id: string = INSTANCE_ID
  networking_method: number = 1
  dhcp: boolean = true
  hostname: string = 'FlClash-ohos'
  network_name: string = ''
  network_secret: string = ''
  peer_urls: string[] = []
  listener_urls: string[] = []
  no_tun: boolean = true
  disable_ipv6: boolean = true
}

interface RuntimePeerConnection {
  isClosed: boolean
}

interface RuntimePeer {
  conns: RuntimePeerConnection[]
}

interface RuntimeNode {
  virtualIpv4: string | null
  virtualIpv4Cidr: string | null
  peerId: number | null
}

interface RuntimeRoute {
  ipv4: string | null
  ipv4Cidr: string | null
  proxyCidrs: string[]
}

interface RuntimeInstance {
  instanceId: string
  running: boolean
  errorMessage: string | null
  myNodeInfo: RuntimeNode | null
  peers: RuntimePeer[]
  routes: RuntimeRoute[]
}

interface RuntimeState {
  instances: RuntimeInstance[]
}

export default class EasyTierManager {
  private active: boolean = false
  private nativeStarted: boolean = false
  private generation: number = 0
  private pump: Promise<void> | undefined
  private failure: Error | undefined
  private networkSecret: string = ''
  private configRoot: string
  private onFailure: () => void
  private onLog: (level: string, message: string) => void
  private logTimer: number | undefined
  private recentLogs: string[] = []
  private logReadFailed: boolean = false
  private failureLogged: boolean = false
  private onRoutes: (snapshot: EasyTierRouteSnapshot) => void
  private routeSessionId: string = ''
  private routeConfigTag: string = ''
  private routeRevision: number = 0
  private routeStatus: EasyTierRouteStatus | undefined
  private routeCidrs: string[] = []
  private routesReady: boolean = false
  private nextRouteRead: number = 0
  private routeReadFailed: boolean = false

  constructor(configRoot: string, onFailure: () => void, onLog: (level: string, message: string) => void,
    onRoutes: (snapshot: EasyTierRouteSnapshot) => void) {
    this.configRoot = configRoot
    this.onFailure = onFailure
    this.onLog = onLog
    this.onRoutes = onRoutes
  }

  private log(level: string, message: string): void {
    try {
      this.onLog(level, sanitizeStartupMessage(message, this.networkSecret).slice(0, 2400))
    } catch (logError) {
      // 日志传输失败不能改变网络生命周期。
    }
  }

  private reportFailure(message: string): void {
    if (this.failureLogged) return
    this.failureLogged = true
    this.log('error', message)
  }

  private drainNativeLogs(discard: boolean = false): void {
    try {
      const lines = easyTier.drainLogLines()
      if (discard) {
        this.recentLogs = []
        return
      }
      for (const line of lines) {
        const safeLine = sanitizeStartupMessage(line, this.networkSecret)
        this.recentLogs.push(safeLine.slice(0, 240))
        if (this.recentLogs.length > 6) this.recentLogs.shift()
        const nativeLevel = Number(line.slice(0, line.indexOf('[')))
        // native_log.rs: TRACE=2, DEBUG=3, INFO=4, ERROR=5, WARN=6。
        const level = nativeLevel === 5 ? 'error' : nativeLevel === 6 ? 'warning' :
          nativeLevel === 2 || nativeLevel === 3 ? 'debug' : 'info'
        this.log(level, safeLine)
      }
    } catch (logError) {
      if (!this.logReadFailed) {
        this.logReadFailed = true
        this.log('warning', startupErrorMessage('读取内核日志失败', logError as Error, this.networkSecret))
      }
    }
  }

  private stopLogTimer(): void {
    if (this.logTimer !== undefined) clearInterval(this.logTimer)
    this.logTimer = undefined
  }

  private startLogTimer(generation: number): void {
    this.stopLogTimer()
    this.logTimer = setInterval(() => {
      if (generation !== this.generation) return
      if (!this.active) {
        this.stopLogTimer()
        return
      }
      this.drainNativeLogs()
      if (this.routesReady && Date.now() >= this.nextRouteRead) {
        this.nextRouteRead = Date.now() + 2000
        this.refreshRoutes(generation)
      }
    }, 1000)
  }

  private readRuntimeInstance(): RuntimeInstance | undefined {
    const raw = easyTier.collectRuntimeStateJson()
    if (typeof raw !== 'string' || raw.length > MAX_RUNTIME_JSON_LENGTH) {
      throw new Error('运行状态超出路由同步限制')
    }
    const state = JSON.parse(raw) as RuntimeState
    if (!Array.isArray(state.instances) || state.instances.length > MAX_ROUTE_CANDIDATES) {
      throw new Error('运行状态实例列表无效')
    }
    return state.instances.find((item) => item.instanceId === INSTANCE_ID)
  }

  private hasLivePeer(instance: RuntimeInstance): boolean {
    // 配置快照也会伪造连接；只有实时节点信息具有 peerId。
    return instance.running && !!instance.myNodeInfo?.virtualIpv4 &&
      typeof instance.myNodeInfo?.peerId === 'number' && Number.isFinite(instance.myNodeInfo.peerId) &&
      instance.myNodeInfo.peerId >= 0 && Array.isArray(instance.peers) &&
      instance.peers.some((peer) => Array.isArray(peer.conns) && peer.conns.some((conn) => !conn.isClosed))
  }

  private readRouteCidrs(instance: RuntimeInstance): string[] {
    if (!Array.isArray(instance.routes) || instance.routes.length > MAX_ROUTE_CANDIDATES) {
      throw new Error('路由列表超出同步限制')
    }
    const candidates: string[] = []
    let candidateCount = 0
    const add = (value: string | null | undefined, addressOnly: boolean = false): void => {
      if (value === null || value === undefined || value === '') return
      if (++candidateCount > MAX_ROUTE_CANDIDATES) throw new Error('路由数量超出同步限制')
      if (typeof value !== 'string' || value.length > 64) throw new Error('路由字段无效')
      const cidr = addressOnly ? `${value}/32` : value
      if (!/^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/.test(cidr)) return
      candidates.push(cidr)
    }
    const node = instance.myNodeInfo
    add(node?.virtualIpv4Cidr ?? node?.virtualIpv4, !node?.virtualIpv4Cidr)
    for (const route of instance.routes) {
      add(route.ipv4Cidr ?? route.ipv4, !route.ipv4Cidr)
      if (!Array.isArray(route.proxyCidrs) || route.proxyCidrs.length > MAX_ROUTE_CANDIDATES) {
        throw new Error('子网路由列表超出同步限制')
      }
      for (const cidr of route.proxyCidrs) add(cidr)
    }
    return Array.from(new Set<string>(candidates)).sort()
  }

  private publishRoutes(status: EasyTierRouteStatus, cidrs: string[]): void {
    if (!this.routeSessionId || (status === this.routeStatus && cidrs.join('\n') === this.routeCidrs.join('\n'))) return
    this.routeStatus = status
    this.routeCidrs = cidrs.slice()
    const snapshot: EasyTierRouteSnapshot = {
      sessionId: this.routeSessionId,
      configTag: this.routeConfigTag,
      revision: ++this.routeRevision,
      status,
      cidrs: cidrs.slice(),
    }
    try {
      this.onRoutes(snapshot)
    } catch (routeError) {
      this.log('warning', '路由事件传输失败，保留最新快照')
    }
    if (status === 'ready') this.log('info', `自动路由快照已更新，网段数=${cidrs.length}`)
  }

  private updateRoutes(instance: RuntimeInstance, generation: number): void {
    if (!this.active || generation !== this.generation || !this.hasLivePeer(instance) || instance.errorMessage) return
    try {
      const cidrs = this.readRouteCidrs(instance)
      if (this.active && generation === this.generation) this.publishRoutes('ready', cidrs)
      this.routeReadFailed = false
    } catch (routeError) {
      if (!this.routeReadFailed) this.log('warning', '读取自动路由快照失败，保留已有网段')
      this.routeReadFailed = true
    }
  }

  private refreshRoutes(generation: number): void {
    try {
      const instance = this.readRuntimeInstance()
      if (instance) this.updateRoutes(instance, generation)
    } catch (routeError) {
      if (!this.routeReadFailed) this.log('warning', '读取自动路由快照失败，保留已有网段')
      this.routeReadFailed = true
    }
  }

  async start(props: EasyTierProps, connection: vpnExtension.VpnConnection, configTag: string = ''): Promise<void> {
    let stage = 'EasyTier 清理上次实例'
    try {
      this.log('info', stage)
      const stopping = this.stop()
      const stopGeneration = this.generation
      await stopping
      if (stopGeneration !== this.generation) throw new Error('EasyTier 启动已取消')
      if (!props.enable) return
      this.networkSecret = props.networkSecret
      this.routeSessionId = util.generateRandomUUID(true)
      this.routeConfigTag = configTag
      this.routeRevision = 0
      this.routeStatus = undefined
      this.routeCidrs = []
      this.routesReady = false
      this.routeReadFailed = false
      this.publishRoutes('starting', [])
      this.failure = undefined
      this.failureLogged = false
      this.logReadFailed = false
      this.log('info', '初始化内核日志（仅内存）')
      try {
        easyTier.initTracingSubscriber()
        easyTier.configureLogManager(true, false)
      } catch (logError) {
        this.log('warning', startupErrorMessage('初始化内核日志失败', logError as Error, this.networkSecret))
      }
      this.drainNativeLogs(true)
      stage = 'EasyTier 初始化配置'
      this.log('info', stage)
      if (!easyTier.initConfigStore(this.configRoot)) {
        throw new Error('私有配置存储初始化失败')
      }
      const config = new EmbeddedNetworkConfig()
      config.network_name = props.networkName
      config.network_secret = props.networkSecret
      config.peer_urls = props.peerUrls
      this.active = true
      const generation = ++this.generation
      this.startLogTimer(generation)
      stage = 'EasyTier 启用套接字保护'
      this.log('info', stage)
      if (!easyTier.enableSocketProtection()) {
        this.active = false
        throw new Error('套接字保护未启用')
      }
      this.pump = this.protectSockets(connection, generation)
      this.nativeStarted = true
      stage = 'EasyTier 启动内核'
      this.log('info', stage)
      if (!easyTier.runEmbeddedNetworkInstance(JSON.stringify(config), SOCKS_PORT)) {
        throw new Error('内核未启动')
      }
      this.drainNativeLogs()
      stage = 'EasyTier 等待节点连接'
      this.log('info', stage)
      await this.waitForPeer(generation)
      this.log('info', '启动完成，内置 SOCKS5 端口 17890')
    } catch (error) {
      let message = this.failure?.message ?? this.captureFailure(stage, error as Error)
      this.reportFailure(message)
      try {
        await this.stop()
      } catch (cleanupError) {
        const cleanupMessage = startupErrorMessage('EasyTier 清理失败', cleanupError as Error, this.networkSecret)
        this.log('warning', cleanupMessage)
        message += `\n${cleanupMessage}`
      }
      const failure = new Error(message.slice(0, 2400))
      this.failure = failure
      throw failure
    }
  }

  private captureFailure(stage: string, error: Error): string {
    let message = startupErrorMessage(stage, error, this.networkSecret).slice(0, 800)
    this.drainNativeLogs()
    if (this.recentLogs.length > 0) message += `\n内核日志:\n${this.recentLogs.join('\n')}`
    return message
  }

  cancel(): void {
    this.stopLogTimer()
    this.active = false
    this.routesReady = false
    this.publishRoutes('stopped', [])
    ++this.generation
    if (this.pump || this.nativeStarted) easyTier.failSocketProtection()
  }

  async stop(): Promise<void> {
    const hadWork = this.active || this.pump !== undefined || this.nativeStarted
    if (hadWork) {
      this.log('info', '停止实例并等待套接字保护队列结束')
      this.drainNativeLogs()
    }
    this.cancel()
    await this.pump
    this.pump = undefined
    if (this.nativeStarted) {
      this.log('info', '停止内核')
      if (!easyTier.stopEmbeddedNetworkInstance()) {
        throw new Error('EasyTier instance could not stop')
      }
      this.nativeStarted = false
    }
    if (hadWork) this.log('info', '关闭套接字保护')
    easyTier.disableSocketProtection()
    if (hadWork) {
      this.drainNativeLogs()
      this.log('info', '清理完成')
    }
  }

  private async protectSockets(connection: vpnExtension.VpnConnection, generation: number): Promise<void> {
    let firstSocket = true
    try {
      while (this.active && generation === this.generation) {
        const request = await easyTier.nextSocketProtectionRequest()
        if (!request) {
          if (this.active && generation === this.generation) {
            throw new Error('EasyTier socket protection stopped unexpectedly')
          }
          return
        }
        if (!this.active || generation !== this.generation) {
          easyTier.completeSocketProtection(request.requestId, false, 'VPN stopped')
          return
        }
        try {
          if (firstSocket) this.log('info', '保护首个内核套接字')
          await connection.protect(request.socketFd)
          easyTier.completeSocketProtection(
            request.requestId,
            this.active && generation === this.generation,
            undefined,
          )
          if (firstSocket) this.log('info', '首个内核套接字保护完成')
          firstSocket = false
        } catch (error) {
          const failure = new Error(this.captureFailure('EasyTier VPN 套接字保护', error as Error))
          this.failure = failure
          easyTier.completeSocketProtection(request.requestId, false, failure.message)
          throw failure
        }
      }
    } catch (error) {
      if (this.active && generation === this.generation) {
        this.failure = this.failure ?? new Error(this.captureFailure('EasyTier 套接字保护队列', error as Error))
        this.reportFailure(this.failure.message)
        this.cancel()
        this.onFailure()
      }
    }
  }

  private async waitForPeer(generation: number): Promise<void> {
    const deadline = Date.now() + 30000
    let nextProgress = 0
    while (this.active && generation === this.generation) {
      const instance = this.readRuntimeInstance()
      if (Date.now() >= nextProgress) {
        const peers = instance?.peers?.filter((peer) => peer.conns.some((conn) => !conn.isClosed)).length ?? 0
        this.log('info', `连接状态：running=${instance?.running ?? false}，已连接节点=${peers}，虚拟 IPv4=${instance?.myNodeInfo?.virtualIpv4 ?? '未分配'}`)
        this.drainNativeLogs()
        nextProgress = Date.now() + 5000
      }
      if (instance?.errorMessage) throw new Error(instance.errorMessage)
      if (instance && this.hasLivePeer(instance)) {
        this.routesReady = true
        this.nextRouteRead = Date.now() + 2000
        this.updateRoutes(instance, generation)
        return
      }
      if (Date.now() >= deadline) throw new Error('节点连接超时（30 秒）')
      await new Promise<void>((resolve) => { setTimeout(resolve, 250) })
    }
    throw this.failure ?? new Error('EasyTier 启动已取消')
  }
}

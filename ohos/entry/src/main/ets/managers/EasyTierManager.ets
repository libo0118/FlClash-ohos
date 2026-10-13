import { vpnExtension } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import easyTier from 'easytier-ohrs'
import { EasyTierProps } from '../models/State'

const INSTANCE_ID = '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0'
const SOCKS_PORT = 17890

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
}

interface RuntimeInstance {
  instanceId: string
  running: boolean
  errorMessage: string | null
  myNodeInfo: RuntimeNode | null
  peers: RuntimePeer[]
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

  constructor(configRoot: string, onFailure: () => void) {
    this.configRoot = configRoot
    this.onFailure = onFailure
  }

  async start(props: EasyTierProps, connection: vpnExtension.VpnConnection): Promise<void> {
    let stage = 'EasyTier 清理上次实例'
    try {
      await this.stop()
      if (!props.enable) return
      this.networkSecret = props.networkSecret
      this.failure = undefined
      stage = 'EasyTier 初始化配置'
      try {
        easyTier.drainLogLines()
      } catch (logError) {
        // 日志读取失败不应阻止网络启动。
      }
      if (!easyTier.initConfigStore(this.configRoot)) {
        throw new Error('私有配置存储初始化失败')
      }
      const config = new EmbeddedNetworkConfig()
      config.network_name = props.networkName
      config.network_secret = props.networkSecret
      config.peer_urls = props.peerUrls
      this.active = true
      const generation = ++this.generation
      stage = 'EasyTier 启用套接字保护'
      if (!easyTier.enableSocketProtection()) {
        this.active = false
        throw new Error('套接字保护未启用')
      }
      this.pump = this.protectSockets(connection, generation)
      this.nativeStarted = true
      stage = 'EasyTier 启动内核'
      if (!easyTier.runEmbeddedNetworkInstance(JSON.stringify(config), SOCKS_PORT)) {
        throw new Error('内核未启动')
      }
      stage = 'EasyTier 等待节点连接'
      await this.waitForPeer(generation)
    } catch (error) {
      let message = this.failure?.message ?? this.captureFailure(stage, error as Error)
      try {
        await this.stop()
      } catch (cleanupError) {
        message += `\n${startupErrorMessage('EasyTier 清理失败', cleanupError as Error, this.networkSecret)}`
      }
      const failure = new Error(message.slice(0, 2400))
      this.failure = failure
      throw failure
    }
  }

  private captureFailure(stage: string, error: Error): string {
    let message = startupErrorMessage(stage, error, this.networkSecret).slice(0, 800)
    try {
      const lines = easyTier.drainLogLines().slice(-6).map((line: string) => {
        return sanitizeStartupMessage(line, this.networkSecret).slice(0, 240)
      })
      if (lines.length > 0) message += `\n内核日志:\n${lines.join('\n')}`
    } catch (logError) {
      // 原始启动错误必须在日志不可用时仍能返回。
    }
    return message
  }

  cancel(): void {
    this.active = false
    ++this.generation
    if (this.pump || this.nativeStarted) easyTier.failSocketProtection()
  }

  async stop(): Promise<void> {
    this.cancel()
    await this.pump
    this.pump = undefined
    if (this.nativeStarted) {
      if (!easyTier.stopEmbeddedNetworkInstance()) {
        throw new Error('EasyTier instance could not stop')
      }
      this.nativeStarted = false
    }
    easyTier.disableSocketProtection()
  }

  private async protectSockets(connection: vpnExtension.VpnConnection, generation: number): Promise<void> {
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
          await connection.protect(request.socketFd)
          easyTier.completeSocketProtection(
            request.requestId,
            this.active && generation === this.generation,
            undefined,
          )
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
        this.cancel()
        this.onFailure()
      }
    }
  }

  private async waitForPeer(generation: number): Promise<void> {
    const deadline = Date.now() + 30000
    while (this.active && generation === this.generation) {
      const state = JSON.parse(easyTier.collectRuntimeStateJson()) as RuntimeState
      const instance = state.instances.find((item) => item.instanceId === INSTANCE_ID)
      if (instance?.errorMessage) throw new Error(instance.errorMessage)
      if (instance?.running && instance.myNodeInfo?.virtualIpv4 &&
        instance.peers.some((peer) => peer.conns.some((conn) => !conn.isClosed))) {
        return
      }
      if (Date.now() >= deadline) throw new Error('节点连接超时（30 秒）')
      await new Promise<void>((resolve) => { setTimeout(resolve, 250) })
    }
    throw this.failure ?? new Error('EasyTier 启动已取消')
  }
}

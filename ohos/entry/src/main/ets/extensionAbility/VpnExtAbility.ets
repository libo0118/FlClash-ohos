import { vpnExtension, VpnExtensionAbility, connection } from '@kit.NetworkKit'
import { Want, bundleManager } from '@kit.AbilityKit'
import { rpc } from '@kit.IPCKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { setEventListener, invokeAction, startTUN, stopTun, forceGC, suspend, updateDns, quickSetup } from 'core'
import { AccessControlMode, VpnOptions } from '../models/State'
import { ChunkedSender, ChunkedReader } from '../utils/Rpc'
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import PowerManager from '../managers/PowerManager'
import NetworkManager from '../managers/NetworkManager'
import EasyTierManager, { sanitizeStartupMessage, startupErrorMessage } from '../managers/EasyTierManager'

const IPV4_ADDRESS = "172.19.0.1/30"
const IPV6_ADDRESS = "fdfe:dcba:9876::1/126"
const DNS = "172.19.0.2"
const DNS6 = "fdfe:dcba:9876::2"
const NET_ANY = "0.0.0.0"
const NET_ANY6 = "::"

export enum RPCType{
  invokeAction,
  quickSetup,
  updateNotificationParams,
  startService,
  stopService,
  setEventListener,
  setCrashlytics,
  getRunTime,
}

export class ServiceStub extends rpc.RemoteObject {
  private parent: VpnExtAbility
  private reader: ChunkedReader = new ChunkedReader()

  constructor(descriptor: string, parent: VpnExtAbility) {
    super(descriptor)
    this.parent = parent
  }

  onRemoteMessageRequest(code: number, send: rpc.MessageSequence, reply: rpc.MessageSequence, option: rpc.MessageOption): boolean | Promise<boolean> {
    if (code === RPCType.setEventListener) {
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleSetEventListener(remote)
      return true
    } else if (code === RPCType.invokeAction) {
      const data = this.reader.read(send)
      if (data === null) return true
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleInvokeAction(data, remote)
      return true
    } else if (code === RPCType.startService) {
      const raw = this.reader.read(send)
      if (raw === null) return true
      const vpnOptions = JSON.parse(raw) as VpnOptions
      const runTime = send.readLong()
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleStartService(vpnOptions, runTime, remote)
      return true
    } else if (code === RPCType.stopService) {
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleStopService(remote)
      return true
    } else if (code === RPCType.getRunTime) {
      this.parent.handleGetRunTime(reply)
      return true
    } else if (code === RPCType.quickSetup) {
      const setupParams = this.reader.read(send)
      if (setupParams === null) return true
      const initParams = send.readString()
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleQuickSetup(initParams, setupParams, remote)
      return true
    } else if (code === RPCType.updateNotificationParams) {
      return true
    } else if (code === RPCType.setCrashlytics) {
      return true
    } else {
      return false
    }
  }
}

export default class VpnExtAbility extends VpnExtensionAbility {
  private service: ServiceStub | undefined
  private vpnConnection: vpnExtension.VpnConnection | undefined
  private vpnId: string | undefined
  private powerManager: PowerManager | undefined
  private networkManager: NetworkManager | undefined
  private runTime: number = 0
  private sender: ChunkedSender = new ChunkedSender()
  private uidBundleNameMap: Map<number, string> = new Map<number, string>()
  private easyTier: EasyTierManager | undefined
  private operation: Promise<void> = Promise.resolve()
  private startGeneration: number = 0
  private tunStarted: boolean = false
  private destroyed: boolean = false

  onCreate(want: Want): void {
    this.vpnConnection = vpnExtension.createVpnConnection(this.context)
    this.powerManager = new PowerManager()
    this.networkManager = new NetworkManager()
    this.easyTier = new EasyTierManager(`${this.context.filesDir}/easytier`, () => {
      ++this.startGeneration
      this.enqueue(async () => { await this.stopVpn() })
    })
  }

  onDestroy(): void {
    this.destroyed = true
    ++this.startGeneration
    this.easyTier?.cancel()
    this.enqueue(async () => { await this.stopVpn() })
  }

  onConnect(want: Want): rpc.RemoteObject {
    if (!this.service) this.service = new ServiceStub("ServiceStub", this)
    return this.service
  }

  onDisconnect(want: Want): void {
    setEventListener()
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) forceGC()
  }

  private toLinkAddress(cidr: string, family: number): vpnExtension.LinkAddress {
    const parts = cidr.split('/')
    const address: connection.NetAddress = { address: parts[0], family }
    return { address, prefixLength: Number(parts[1]) }
  }

  private toRouteInfo(cidr: string, family: number): vpnExtension.RouteInfo {
    const destination = this.toLinkAddress(cidr, family)
    const gateway: connection.NetAddress = { address: '', family }
    return {
      interface: '',
      destination,
      gateway,
      hasGateway: false,
      isDefaultRoute: destination.prefixLength === 0,
    }
  }

  private toVpnConfig(options: VpnOptions): vpnExtension.VpnConfig {
    const ipv4RouteAddress = options.routeAddress.filter((it) => !it.includes(':'))
    const ipv6RouteAddress = options.routeAddress.filter((it) => it.includes(':'))
    if (options.easyTier?.enable && ipv4RouteAddress.length > 0) {
      for (const cidr of options.easyTier.cidrs) {
        if (!ipv4RouteAddress.includes(cidr)) ipv4RouteAddress.push(cidr)
      }
    }

    const addresses: vpnExtension.LinkAddress[] = [this.toLinkAddress(IPV4_ADDRESS, 1)]
    const routes: vpnExtension.RouteInfo[] = ipv4RouteAddress.length > 0
      ? ipv4RouteAddress.map((it) => this.toRouteInfo(it, 1))
      : [this.toRouteInfo(`${NET_ANY}/0`, 1)]
    const dnsAddresses: string[] = [DNS]

    if (options.ipv6) {
      addresses.push(this.toLinkAddress(IPV6_ADDRESS, 2))
      routes.push(...(ipv6RouteAddress.length > 0
        ? ipv6RouteAddress.map((it) => this.toRouteInfo(it, 2))
        : [this.toRouteInfo(`${NET_ANY6}/0`, 2)]))
      dnsAddresses.push(DNS6)
    }

    const config: vpnExtension.VpnConfig = {
      addresses,
      routes,
      dnsAddresses,
      mtu: 9000,
      isIPv4Accepted: true,
      isIPv6Accepted: options.ipv6,
      isBlocking: !options.allowBypass,
    }

    const accessControl = options.accessControlProps
    if (accessControl.enable) {
      if (accessControl.mode === AccessControlMode.ACCEPT_SELECTED) {
        config.trustedApplications = [...accessControl.acceptList, this.context.applicationInfo.name]
      } else {
        config.blockedApplications = accessControl.rejectList.filter((it) => it !== this.context.applicationInfo.name)
      }
    }

    return config
  }

  private toTunAddress(options: VpnOptions): string {
    const addresses = [IPV4_ADDRESS]
    if (options.ipv6) {
      addresses.push(IPV6_ADDRESS)
    }
    return addresses.join(',')
  }

  private toTunDns(options: VpnOptions): string {
    if (options.dnsHijacking) {
      return NET_ANY
    }
    const dns = [DNS]
    if (options.ipv6) {
      dns.push(DNS6)
    }
    return dns.join(',')
  }

  private toNetAddress(addr: string): connection.NetAddress {
    const separator = addr.lastIndexOf(':')
    const host = addr.slice(0, separator)
    const port = Number(addr.slice(separator + 1))
    const address = host.startsWith('[') && host.endsWith(']') ? host.slice(1, -1) : host
    const family = address.includes(':') ? 2 : 1
    return { address, family, port }
  }

  private resolverProcess(protocol: number, source: string, target: string, uid: number): string {
    const nextUid = deviceInfo.sdkApiVersion >= 23 ?
      connection.getConnectOwnerUidSync(protocol, this.toNetAddress(source), this.toNetAddress(target)) : uid
    if (nextUid === -1) return ''
    if (!this.uidBundleNameMap.has(nextUid)) {
      try {
        this.uidBundleNameMap.set(nextUid, bundleManager.getBundleNameByUidSync(nextUid))
      } catch (err) {
        this.uidBundleNameMap.set(nextUid, '')
      }
    }

    return this.uidBundleNameMap.get(nextUid) ?? ''
  }

  private sendCallback(remote: rpc.RemoteObject, data: string): void {
    this.sender.send(remote, 0, data, null)
  }

  private sendResult(remote: rpc.RemoteObject, runTime: number, error: string = ''): void {
    const options = new rpc.MessageOption()
    const send = rpc.MessageSequence.create()
    const reply = rpc.MessageSequence.create()
    options.setAsync(false)
    send.writeLong(runTime)
    send.writeString(error)
    remote.sendMessageRequest(0, send, reply, options).finally(() => {
      send.reclaim()
      reply.reclaim()
    })
  }

  handleSetEventListener(remote: rpc.RemoteObject): void {
    setEventListener((callbackData: string) => { this.sendCallback(remote, callbackData) })
  }

  handleInvokeAction(data: string, remote: rpc.RemoteObject): void {
    invokeAction((callbackData: string) => { this.sendCallback(remote, callbackData) }, data)
  }

  private enqueue(action: () => Promise<void>, remote?: rpc.RemoteObject, networkSecret: string = ''): void {
    let error = ''
    this.operation = this.operation.then(action).catch(async (err: Error) => {
      error = sanitizeStartupMessage(err.message ?? 'VPN 操作失败', networkSecret).slice(0, 2400)
      console.error(`VPN operation failed: ${error}`)
      try {
        await this.stopVpn()
      } catch (cleanupError) {
        console.error('VPN cleanup failed')
      }
    }).finally(() => {
      if (remote) this.sendResult(remote, this.runTime, error)
    })
  }

  private async stopVpn(): Promise<void> {
    this.runTime = 0
    try {
      await this.easyTier?.stop()
    } finally {
      if (this.tunStarted) stopTun()
      this.tunStarted = false
      this.vpnId = undefined
      this.powerManager?.unsubscribe()
      this.networkManager?.unsubscribe()
      await this.vpnConnection?.destroy().catch(() => {})
    }
  }

  handleStartService(vpnOptions: VpnOptions, runTime: number, remote: rpc.RemoteObject): void {
    const generation = ++this.startGeneration
    this.easyTier?.cancel()
    let stage = 'VPN 清理旧连接'
    const networkSecret = vpnOptions.easyTier?.networkSecret ?? ''
    this.enqueue(async () => {
      try {
        if (this.destroyed || generation !== this.startGeneration) return
        await this.stopVpn()
        if (this.destroyed || generation !== this.startGeneration) return
        stage = 'VPN 校验配置'
        if (vpnOptions.easyTier?.enable && (!vpnOptions.enable || vpnOptions.port === 17890)) {
          throw new Error('EasyTier requires VPN and a separate SOCKS port')
        }
        const connection = this.vpnConnection
        if (!connection) throw new Error('VPN connection is unavailable')
        if (vpnOptions.enable) {
          stage = 'VPN 创建连接'
          const fd = await connection.create(this.toVpnConfig(vpnOptions))
          if (this.destroyed || generation !== this.startGeneration) {
            await this.stopVpn()
            return
          }
          stage = 'VPN 启动代理 TUN'
          startTUN(
            (socketFd: number): Promise<void> => connection.protect(socketFd),
            (protocol: number, source: string, target: string, uid: number) => this.resolverProcess(protocol, source, target, uid),
            fd,
            vpnOptions.stack,
            this.toTunAddress(vpnOptions),
            this.toTunDns(vpnOptions),
          )
          this.tunStarted = true
          if (vpnOptions.easyTier?.enable) {
            stage = 'EasyTier 启动'
            await this.easyTier?.start(vpnOptions.easyTier, connection)
          }
          stage = 'VPN 生成连接标识'
          this.vpnId = deviceInfo.sdkApiVersion >= 20
            ? await connection.generateVpnId()
            : util.generateRandomUUID(true)
        }
        if (this.destroyed || generation !== this.startGeneration) {
          await this.stopVpn()
          return
        }
        stage = 'VPN 订阅状态'
        this.powerManager?.subscribe(suspend)
        this.networkManager?.subscribe(updateDns)
        this.runTime = runTime !== 0 ? runTime : Date.now()
      } catch (error) {
        throw new Error(startupErrorMessage(stage, error as Error, networkSecret))
      }
    }, remote, networkSecret)
  }

  handleStopService(remote: rpc.RemoteObject): void {
    ++this.startGeneration
    this.easyTier?.cancel()
    this.enqueue(async () => { await this.stopVpn() }, remote)
  }

  handleGetRunTime(reply: rpc.MessageSequence): void {
    reply.writeLong(this.runTime)
  }

  handleQuickSetup(initParams: string, setupParams: string, remote: rpc.RemoteObject): void {
    quickSetup((callbackData: string) => { this.sendCallback(remote, callbackData) }, initParams, setupParams)
  }
}


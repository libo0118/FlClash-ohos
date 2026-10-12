import { vpnExtension } from '@kit.NetworkKit'
import easyTier from 'easytier-ohrs'
import { EasyTierProps } from '../models/State'

const INSTANCE_ID = '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0'
const SOCKS_PORT = 17890

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
  private configRoot: string
  private onFailure: () => void

  constructor(configRoot: string, onFailure: () => void) {
    this.configRoot = configRoot
    this.onFailure = onFailure
  }

  async start(props: EasyTierProps, connection: vpnExtension.VpnConnection): Promise<void> {
    await this.stop()
    if (!props.enable) return
    if (!easyTier.initConfigStore(this.configRoot)) {
      throw new Error('EasyTier private configuration storage could not start')
    }
    const config = new EmbeddedNetworkConfig()
    config.network_name = props.networkName
    config.network_secret = props.networkSecret
    config.peer_urls = props.peerUrls
    this.failure = undefined
    this.active = true
    const generation = ++this.generation
    if (!easyTier.enableSocketProtection()) {
      this.active = false
      throw new Error('EasyTier socket protection could not start')
    }
    this.pump = this.protectSockets(connection, generation)
    this.nativeStarted = true
    try {
      if (!easyTier.runEmbeddedNetworkInstance(JSON.stringify(config), SOCKS_PORT)) {
        throw new Error('EasyTier configuration could not start')
      }
      await this.waitForPeer(generation)
    } catch (error) {
      await this.stop()
      throw new Error((error as Error).message)
    }
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
          easyTier.completeSocketProtection(request.requestId, false, 'VPN socket protection failed')
          throw new Error('EasyTier VPN socket protection failed')
        }
      }
    } catch (error) {
      if (this.active && generation === this.generation) {
        this.failure = new Error('EasyTier VPN socket protection failed')
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
      if (instance?.errorMessage) throw new Error('EasyTier native instance failed')
      if (instance?.running && instance.myNodeInfo?.virtualIpv4 &&
        instance.peers.some((peer) => peer.conns.some((conn) => !conn.isClosed))) {
        return
      }
      if (Date.now() >= deadline) throw new Error('EasyTier peer connection timed out')
      await new Promise<void>((resolve) => { setTimeout(resolve, 250) })
    }
    throw this.failure ?? new Error('EasyTier start was cancelled')
  }
}

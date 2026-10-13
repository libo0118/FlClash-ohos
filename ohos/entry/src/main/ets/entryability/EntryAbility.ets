
import { FlutterAbility, FlutterEngine, MethodResult } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { common, Want, bundleManager } from '@kit.AbilityKit';
import { antifraudPicker } from '@kit.DeviceSecurityKit';
import { RPCType } from '../extensionAbility/VpnExtAbility';
import { VpnOptions } from '../models/State';
import { Bundle } from '../models/Bundle';
import { rpc } from '@kit.IPCKit';
import { vpnExtension } from '@kit.NetworkKit';
import { Lock } from '../utils/Lock'
import { publishEvent } from '../utils/Event'
import { ChunkedSender, ChunkedReader } from '../utils/Rpc';
import ServicePlugin from '../plugins/ServicePlugin';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import AppPlugin from '../plugins/AppPlugin';
import NotificationManager from '../managers/NotificationManager';
import VpnCardManager, { VpnCardReply, VpnCardRequest } from '../managers/VpnCardManager';

interface Connection {
  id: number
  remote: rpc.RemoteObject
}

export class CallbackStub extends rpc.RemoteObject {
  private onResult: (data: string) => void | undefined
  private reader: ChunkedReader = new ChunkedReader()
  constructor(descriptor: string, onResult: (data: string) => void) {
    super(descriptor)
    this.onResult = onResult
  }

  onRemoteMessageRequest(code: number, send: rpc.MessageSequence, reply: rpc.MessageSequence, option: rpc.MessageOption): boolean | Promise<boolean> {
    const data = this.reader.read(send)
    if (data !== null) this.onResult(data)
    return true
  }
}

export class ResultStub extends rpc.RemoteObject {
  private onResult: (data: number, error: string) => void
  constructor(descriptor: string, onResult: (data: number, error: string) => void) {
    super(descriptor)
    this.onResult = onResult
  }

  onRemoteMessageRequest(code: number, send: rpc.MessageSequence, reply: rpc.MessageSequence, option: rpc.MessageOption): boolean | Promise<boolean> {
    const data = send.readLong()
    const error = send.readString()
    this.onResult(data, error)
    return true
  }
}

export default class EntryAbility extends FlutterAbility {
  private servicePlugin: ServicePlugin | undefined
  private sender: ChunkedSender = new ChunkedSender()
  private notificationManager: NotificationManager | undefined
  private connecting: Promise<Connection> | undefined
  private disconnecting: Promise<void> | undefined
  private onDisconnected: ((message: string) => void) | undefined
  private unlock: (() => void) | undefined
  private get lock(): Lock {
    if (!AppStorage.has('ipc_lock')) AppStorage.setOrCreate('ipc_lock', new Lock())
    return AppStorage.get('ipc_lock') as Lock
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine)
    flutterEngine.getPlugins()?.add(new AppPlugin(this))
    this.servicePlugin = new ServicePlugin(this)
    flutterEngine.getPlugins()?.add(this.servicePlugin)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam)
    this.notificationManager = new NotificationManager(this.context)
    this.notificationManager?.subscribe()
    const manager = new VpnCardManager(this.context)
    manager.setReady(false)
    manager.publish('unknown', false)
    this.callee.on('vpnCardToggle', (data: rpc.MessageSequence) => {
      try {
        const request = JSON.parse(data.readString()) as VpnCardRequest
        if (manager.accepts(request) && typeof request.enable === 'boolean') {
          if (this.servicePlugin) this.servicePlugin.requestCardAction(request.enable)
          else manager.publish('unknown', false)
        }
      } catch (_) {}
      return new VpnCardReply()
    })
    this.callee.on('vpnCardRefresh', (data: rpc.MessageSequence) => {
      try {
        const request = JSON.parse(data.readString()) as VpnCardRequest
        if (manager.accepts(request)) {
          if (this.servicePlugin) this.servicePlugin.refreshCard()
          else manager.publish('unknown', false)
        }
      } catch (_) {}
      return new VpnCardReply()
    })
    this.handleCardWant(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam)
    this.handleCardWant(want)
  }

  private pendingCardAction: boolean | undefined

  private handleCardWant(want: Want): void {
    const params = want.parameters
    if (!params || typeof params['vpnCardEnable'] !== 'boolean') return
    const request: VpnCardRequest = {
      formId: params['formId'] as string,
      token: params['token'] as string,
      enable: params['vpnCardEnable'] as boolean,
    }
    if (!new VpnCardManager(this.context).accepts(request)) return
    if (this.servicePlugin) this.servicePlugin.queueCardAction(request.enable as boolean)
    else this.pendingCardAction = request.enable
  }

  takePendingCardAction(): boolean | undefined {
    const pending = this.pendingCardAction
    this.pendingCardAction = undefined
    return pending
  }

  onDestroy(): void {
    this.callee.off('vpnCardToggle')
    this.callee.off('vpnCardRefresh')
    new VpnCardManager(this.context).setReady(false)
    new VpnCardManager(this.context).publish('unknown', false)
    super.onDestroy()
    this.disconnect()
    this.notificationManager?.unsubscribe()
  }

  private connect(): Promise<Connection> {
    return (this.disconnecting ?? Promise.resolve()).then(() => {
      return this.lock.acquire(this.context.abilityInfo.name).then((unlock: () => void) => {
        this.unlock = unlock
        const want: Want = {
          bundleName: this.context.applicationInfo.name,
          abilityName: 'VpnExtAbility',
        }
        return vpnExtension.startVpnExtensionAbility(want).then(() => {
          return this.connectService(want, this.context)
        }).catch((err: Error) => {
          if (this.unlock) {
            this.unlock()
            this.unlock = undefined
          }
          this.connecting = undefined
          this.onDisconnected?.(`Failed to connect VpnExtAbility: ${err.message ?? err}`)
          throw err
        })
      })
    })
  }

  private connectService(want: Want, context: common.UIAbilityContext): Promise<Connection> {
    return new Promise((resolve, reject) => {
      let id = -1
      id = context.connectServiceExtensionAbility(want, {
        onConnect: (elementName: bundleManager.ElementName, remote: rpc.RemoteObject) => {
          resolve({id, remote})
        },
        onDisconnect: (elementName: bundleManager.ElementName) => {
          this.connecting = undefined
          if (this.disconnecting) {
            this.disconnecting.finally(() => {
              if (this.unlock) {
                this.unlock()
                this.unlock = undefined
              }
              this.disconnecting = undefined
            })
          } else {
            if (this.unlock) {
              this.unlock()
              this.unlock = undefined
            }
            this.onDisconnected?.(`${elementName.abilityName} disconnected unexpectedly`)
          }
        },
        onFailed: (code: number) => {
          this.connecting = undefined
          reject(new Error(`connectServiceExtensionAbility failed: ${code}`))
        },
      } as common.ConnectOptions)
    })
  }

  private ensureConnected(): Promise<rpc.RemoteObject> {
    if (!this.connecting){
      this.connecting = this.connect()
      publishEvent('SERVICE_YIELD', '')
    }
    return this.connecting.then((connection: Connection) => connection.remote)
  }

  private disconnect(): Promise<void> {
    if (!this.unlock) this.lock.revoke(this.context.abilityInfo.name)

    if (this.connecting) {
      return this.connecting.then((connection: Connection) => {
        if (!this.disconnecting) this.disconnecting = this.context.disconnectServiceExtensionAbility(connection.id)
        return this.disconnecting
      })
    } else {
      if (this.unlock) {
        this.unlock()
        this.unlock = undefined
      }
      return Promise.resolve()
    }
  }

  handleMoveTaskToBack(result: MethodResult): Promise<void> {
    return this.context.moveAbilityToBackground().finally(() => {
      result.success(true)
    })
  }

  handleGetPackages(result: MethodResult): Promise<void> {
    return antifraudPicker.selectFraudApp(this.context).then((antifraudAppResult: antifraudPicker.AntifraudAppResult) => {
      const bundleList: Bundle[] = []
      for (const singleAntifraudAppInfo of antifraudAppResult.appInfo) {
        bundleList.push({ packageName: singleAntifraudAppInfo.bundleName, label: singleAntifraudAppInfo.label, system: false, internet: true, lastUpdateTime: 0 } as Bundle)
      }
      result.success(JSON.stringify(bundleList))
    }).catch((err: Error) => {
      console.log(`Call getPackages failed <= ${err.message ?? err}`)
      result.success('[]')
    })
  }

  handleInit(callbackStub: CallbackStub): Promise<rpc.RequestResult> {
    return this.ensureConnected().then((remote: rpc.RemoteObject) => {
      const options = new rpc.MessageOption()
      const send = rpc.MessageSequence.create()
      const reply = rpc.MessageSequence.create()
      options.setAsync(true)
      send.writeRemoteObject(callbackStub)
      return remote.sendMessageRequest(RPCType.setEventListener, send, reply, options).finally(() => {
        send.reclaim()
        reply.reclaim()
      })
    })
  }

  handleShutdown(): Promise<void> {
    return this.disconnect()
  }

  handleInvokeAction(data: string, callbackStub: CallbackStub): Promise<rpc.RequestResult> {
    return this.ensureConnected().then((remote: rpc.RemoteObject) => {
      return this.sender.send(remote, RPCType.invokeAction, data, (send: rpc.MessageSequence) => {
        send.writeRemoteObject(callbackStub)
      })
    })
  }

  handleStartService(vpnOptions: VpnOptions, runTime: number, resultStub: ResultStub): Promise<rpc.RequestResult> {
    return this.ensureConnected().then((remote: rpc.RemoteObject) => {
      return this.sender.send(remote, RPCType.startService, JSON.stringify(vpnOptions), (send: rpc.MessageSequence) => {
        send.writeLong(runTime)
        send.writeRemoteObject(resultStub)
      })
    })
  }

  handleStopService(resultStub: ResultStub): Promise<rpc.RequestResult> {
    return this.ensureConnected().then((remote: rpc.RemoteObject) => {
      const options = new rpc.MessageOption()
      const send = rpc.MessageSequence.create()
      const reply = rpc.MessageSequence.create()
      options.setAsync(false)
      send.writeRemoteObject(resultStub)
      return remote.sendMessageRequest(RPCType.stopService, send, reply, options).finally(() => {
        send.reclaim()
        reply.reclaim()
      })
    })
  }

  handleGetRunTime(): Promise<number> {
    return this.ensureConnected().then((remote: rpc.RemoteObject) => {
      const options = new rpc.MessageOption()
      const send = rpc.MessageSequence.create()
      const reply = rpc.MessageSequence.create()
      options.setAsync(false)
      return remote.sendMessageRequest(RPCType.getRunTime, send, reply, options).then((requestResult: rpc.RequestResult) => {
        return requestResult.reply.readLong()
      }).finally(() => {
        send.reclaim()
        reply.reclaim()
      })
    })
  }

  setOnDisconnected(callback: (message: string) => void): void {
    this.onDisconnected = callback
  }
}

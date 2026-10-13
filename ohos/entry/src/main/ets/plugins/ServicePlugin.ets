import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { CallbackStub, ResultStub } from '../entryability/EntryAbility'
import { State, VpnOptions } from '../models/State'
import { publishEvent } from '../utils/Event'
import { globalState, RunState } from '../GlobalState';
import EntryAbility from '../entryability/EntryAbility';
import { sanitizeStartupMessage, startupErrorMessage } from '../managers/EasyTierManager'
import VpnCardManager from '../managers/VpnCardManager'

export default class ServicePlugin implements FlutterPlugin, MethodCallHandler {
  private parent: EntryAbility
  private channel: MethodChannel | undefined
  private cardReady: boolean = false
  private cardPending: boolean = false
  private queuedCardAction: boolean | undefined
  private cardStateRevision: number = 0
  private get cardManager(): VpnCardManager { return new VpnCardManager(this.parent.context) }

  constructor(entryAbility: EntryAbility) {
    this.parent = entryAbility
  }

  getUniqueClassName(): string {
    return "ServicePlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "com.follow.clash/service")
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.cardReady = false
    this.cardPending = false
    this.queuedCardAction = undefined
    ++this.cardStateRevision
    this.cardManager.setReady(false)
    this.cardManager.publish('unknown', false)
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === "init") {
      this.handleInit(result)
    } else if (call.method === "shutdown") {
      this.handleShutdown(result)
    } else if (call.method === "syncState") {
      this.handleSyncState(call, result)
    } else if (call.method === "invokeAction") {
      this.handleInvokeAction(call, result)
    } else if (call.method === "start") {
      this.handleStart(result)
    } else if (call.method === "stop") {
      this.handleStop(result)
    } else if (call.method === "getRunTime") {
      this.handleGetRunTime(result)
    } else if (call.method === 'vpnCardReady') {
      this.cardReady = call.args === true
      this.cardManager.setReady(this.cardReady)
      result.success(true)
      if (!this.cardReady) this.cardManager.publish('unknown', false)
      if (this.cardReady) {
        const parentPending = this.parent.takePendingCardAction()
        const pending = this.queuedCardAction ?? parentPending
        this.queuedCardAction = undefined
        if (pending !== undefined) this.requestCardAction(pending)
        else this.refreshCard()
      }
    } else if (call.method === 'vpnCardComplete') {
      this.cardPending = false
      result.success(true)
      if (call.args === 'failed') this.cardManager.publish('failed')
      else if (call.args === 'openRequired') this.cardManager.publish('unknown', false)
      else this.refreshCard()
    } else {
      result.notImplemented()
    }
  }

  queueCardAction(enable: boolean): void {
    if (this.cardReady) this.requestCardAction(enable)
    else if (this.queuedCardAction === undefined) this.queuedCardAction = enable
  }

  requestCardAction(enable: boolean): void {
    if (!this.cardReady || !this.channel) {
      this.cardManager.publish('unknown', false)
      return
    }
    if (this.cardPending || globalState.runState === RunState.pending) return
    this.cardPending = true
    ++this.cardStateRevision
    this.cardManager.publish(enable ? 'starting' : 'stopping')
    this.channel.invokeMethod('vpnCardToggle', enable)
  }

  refreshCard(): void {
    if (!this.cardReady) {
      this.cardManager.publish('unknown', false)
      return
    }
    if (this.cardPending || globalState.runState === RunState.pending) return
    const revision = this.cardStateRevision
    this.parent.handleGetRunTime().then((runTime: number) => {
      if (revision !== this.cardStateRevision) return
      globalState.runTime = runTime
      if (globalState.runState !== RunState.pending) {
        globalState.runState = runTime === 0 ? RunState.stop : RunState.start
        this.cardManager.publish(runTime === 0 ? 'stopped' : 'connected')
      }
    }).catch(() => { this.cardManager.publish('failed', false) })
  }

  private handleInit(result: MethodResult): void {
    const callbackStub = new CallbackStub("setEventListener", (data: string) => { this.channel?.invokeMethod("event", data) })
    this.parent.handleInit(callbackStub).then(() => {
      result.success("")
    }).catch((err: Error) => {
      result.success(err.message ?? `${err}`)
    })
    this.parent.setOnDisconnected((message: string) => {
      globalState.runTime = 0
      globalState.runState = RunState.stop
      ++this.cardStateRevision
      this.cardPending = false
      this.cardManager.publish('failed', false)
      this.channel?.invokeMethod("crash", message)
      publishEvent('SERVICE_STOP', '')
    })
  }

  private handleShutdown(result: MethodResult): void {
    this.parent.handleShutdown().finally(() => {
      globalState.runTime = 0
      globalState.runState = RunState.stop
      ++this.cardStateRevision
      this.cardManager.publish('stopped')
      result.success(true)
    })
  }

  private handleSyncState(call: MethodCall, result: MethodResult): void {
    globalState.state = JSON.parse(call.args) as State
    this.cardManager.updateSummary(globalState.state.currentProfileName, globalState.state.vpnOptions?.easyTier?.enable ?? false)
    if (globalState.runState !== RunState.pending) {
      globalState.runState = globalState.runTime === 0 ? RunState.stop : RunState.start
      this.cardManager.publish(globalState.runTime === 0 ? 'stopped' : 'connected')
    }
    result.success("")
  }

  private handleInvokeAction(call: MethodCall, result: MethodResult): void {
    const callbackStub = new CallbackStub("invokeAction", (data: string) => { result.success(data) })
    this.parent.handleInvokeAction(call.args, callbackStub)
  }

  private handleStart(result: MethodResult): void {
    if (globalState.runState === RunState.stop) {
      globalState.runState = RunState.pending
      ++this.cardStateRevision
      this.cardManager.publish('starting')
      const options = globalState.state?.vpnOptions ?? new VpnOptions()
      const networkSecret = options.easyTier?.networkSecret ?? ''
      let completed = false
      const finish = (runTime: number, error: string): void => {
        if (completed) return
        completed = true
        const message = sanitizeStartupMessage(error, networkSecret).slice(0, 2400)
        globalState.runTime = message ? 0 : runTime
        globalState.runState = globalState.runTime !== 0 ? RunState.start : RunState.stop
        ++this.cardStateRevision
        this.cardManager.publish(message ? 'failed' : globalState.runTime !== 0 ? 'connected' : 'stopped')
        if (message) {
          result.error('VPN_START_FAILED', message, null)
        } else {
          result.success(runTime !== 0)
        }
      }
      const resultStub = new ResultStub("handleStart", finish)
      this.parent.handleStartService(options, globalState.runTime, resultStub).catch((error: Error) => {
        finish(0, startupErrorMessage('VPN 启动请求', error, networkSecret))
      })
      return
    }
    result.success(globalState.runState === RunState.start)
  }

  private handleStop(result: MethodResult): void {
    if (globalState.runState !== RunState.stop) {
      globalState.runState = RunState.pending
      ++this.cardStateRevision
      this.cardManager.publish('stopping')
      const resultStub = new ResultStub("handleStop", (runTime: number) => {
        globalState.runTime = runTime
        globalState.runState = RunState.stop
        ++this.cardStateRevision
        this.cardManager.publish('stopped')
        result.success(true)
      })
      this.parent.handleStopService(resultStub).catch(() => {
        globalState.runState = RunState.start
        ++this.cardStateRevision
        this.cardManager.publish('failed')
        result.success(false)
      })
      return
    }
    result.success(true)
  }

  private handleGetRunTime(result: MethodResult): void {
    this.parent.handleGetRunTime().then((runTime: number) => {
      globalState.runTime = runTime
      if (globalState.runState !== RunState.pending) {
        globalState.runState = runTime === 0 ? RunState.stop : RunState.start
      }
    }).finally(() => {
      result.success(globalState.runTime)
    })
  }
}

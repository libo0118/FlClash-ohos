// Runs the actual card authorization/command logic, with Harmony APIs mocked.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const { stripTypeScriptTypes } = require('node:module')

const files = new Map()
const updates = []
const commands = []
let token = 0
class Channel {
  constructor(_messenger, name) { this.name = name }
  setMethodCallHandler(handler) { this.handler = handler }
  invokeMethod(method, data) { commands.push({ method, data }) }
}
class FlutterAbility {
  context = { filesDir: '/private/files' }
  callee = { handlers: new Map(), on: (name, callback) => this.callee.handlers.set(name, callback), off: (name) => this.callee.handlers.delete(name) }
  onCreate() {}
  onNewWant() {}
  onDestroy() {}
  configureFlutterEngine() {}
}
const state = { runTime: 0, runState: 'stop', state: {} }
const context = vm.createContext({
  rpc: { RemoteObject: class {}, MessageSequence: class {} },
  fs: {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    readTextSync(name) { if (!files.has(name)) throw Error('missing'); return files.get(name) },
    openSync(name) { return { fd: name } }, writeSync(fd, value) { files.set(fd, value) }, closeSync() {},
    renameSync(from, to) { files.set(to, files.get(from)); files.delete(from) },
  },
  formBindingData: { createFormBindingData: (data) => data },
  formProvider: { updateForm(id, data) { updates.push({ id, data }); return Promise.resolve() } },
  util: { generateRandomUUID: () => `private-token-${++token}` },
  FlutterAbility, MethodChannel: Channel,
  NotificationManager: class { subscribe() {} unsubscribe() {} },
  AppPlugin: class {}, GeneratedPluginRegistrant: { registerWith() {} },
  globalState: state, RunState: { stop: 'stop', start: 'start', pending: 'pending' },
  ChunkedSender: class {}, ChunkedReader: class {}, VpnOptions: class {},
  sanitizeStartupMessage: (message) => message, startupErrorMessage: (stage, error) => `${stage}: ${error.message}`,
  console, publishEvent: () => Promise.resolve(),
})
const root = path.join(__dirname, '../entry/src/main/ets')
for (const file of ['managers/VpnCardManager.ets', 'entryability/EntryAbility.ets', 'plugins/ServicePlugin.ets']) {
  let source = fs.readFileSync(path.join(root, file), 'utf8')
  source = source.replace(/^import[\s\S]*?from\s+['"][^'"]+['"];?[^\S\r\n]*\r?\n/gm, '')
  source = source.replace(/\bexport default /g, '').replace(/\bexport /g, '')
  vm.runInContext(stripTypeScriptTypes(source, { mode: 'transform' }), context, { filename: file })
}
vm.runInContext('globalThis.subject = { VpnCardManager, EntryAbility, ServicePlugin }', context)
const subject = context.subject
const result = { success() {}, error() {}, notImplemented() { throw Error('unexpected method') } }
const settle = () => new Promise(setImmediate)

async function main() {
  const manager = new subject.VpnCardManager({ filesDir: '/private/files' })
  const first = manager.register('10001')
  const second = manager.register('10002')
  assert.equal(first.vpnStatus, 'unknown')
  assert.equal(first.controlReady, false)
  assert.notEqual(first.cardToken, second.cardToken)
  assert.equal(manager.register('10001').cardToken, first.cardToken)
  assert.equal(manager.accepts({ formId: '10001', token: 'forged' }), false)
  assert.equal(manager.accepts({ formId: '10002', token: first.cardToken }), false)
  assert.equal(manager.accepts({ formId: '10001', token: first.cardToken }), true)
  manager.updateSummary('My profile', true)
  manager.setReady(true)
  manager.publish('connected')
  assert.equal(updates.length, 2)
  assert.ok(updates.every(({ data }) => data.vpnStatus === 'connected' && data.controlReady && data.profileName === 'My profile' && data.easyTierEnabled))
  assert.ok(![...files.values()].join('').includes('networkSecret'))
  assert.equal(updates.at(-1).data.easyTierStatus, 'unknown', 'enabled is not proof of overlay connectivity')
  manager.publish('starting')
  manager.setEasyTierStatus('ready')
  assert.equal(updates.at(-1).data.easyTierStatus, 'ready', 'a real route/peer snapshot can become ready during startup')
  assert.equal(updates.at(-1).data.vpnStatus, 'starting', 'overlay readiness does not complete VPN startup')
  manager.setEasyTierStatus('unavailable')
  assert.equal(updates.at(-1).data.easyTierStatus, 'unavailable')
  manager.publish('stopped')
  assert.equal(updates.at(-1).data.easyTierStatus, 'stopped')
  manager.updateSummary('My profile', false)
  manager.setEasyTierStatus('ready')
  assert.equal(updates.at(-1).data.easyTierStatus, 'disabled')
  manager.updateSummary('My profile', true)
  manager.publish('connected')
  // A removed form cannot retain authority to toggle the VPN.
  manager.remove('10002')
  assert.equal(manager.accepts({ formId: '10002', token: second.cardToken }), false)

  const entry = new subject.EntryAbility()
  entry.onCreate({ parameters: {} }, {})
  const packet = (params) => ({ readString: () => JSON.stringify(params) })
  const invalid = { parameters: { formId: '10001', token: 'forged', vpnCardEnable: true } }
  entry.onNewWant(invalid, {})
  assert.equal(entry.takePendingCardAction(), undefined)
  const valid = { formId: '10001', token: first.cardToken }
  entry.onNewWant({ parameters: { ...valid, vpnCardEnable: true } }, {})
  assert.equal(entry.takePendingCardAction(), true)
  assert.equal(entry.takePendingCardAction(), undefined)
  manager.setReady(true)
  manager.publish('connected')
  entry.callee.handlers.get('vpnCardToggle')(packet({ ...valid, enable: true }))
  assert.equal(commands.length, 0, 'cold call cannot pretend Flutter is ready')
  assert.equal(updates.at(-1).data.controlReady, false, 'stale bound cards must recover to an explicit open-app action')
  assert.equal(updates.at(-1).data.vpnStatus, 'unknown')

  entry.handleGetRunTime = async () => 0
  const plugin = new subject.ServicePlugin(entry)
  plugin.onAttachedToEngine({ getBinaryMessenger() {} })
  assert.equal(plugin.coreChannel.name, 'com.follow.clash/core')
  assert.equal(plugin.coreChannel.handler, plugin)
  let coreReply
  entry.handleInvokeMethod = async (request, stub) => {
    assert.deepEqual(JSON.parse(request), { id: '1', method: 'getIsInit', arguments: null })
    stub.onResult(JSON.stringify({ id: '1', result: true }))
  }
  plugin.onMethodCall({ method: 'invokeMethod', args: JSON.stringify({ id: '1', method: 'getIsInit', arguments: null }) }, {
    success(value) { coreReply = JSON.parse(value) },
  })
  assert.deepEqual(coreReply, { id: '1', result: true })
  // Cold router intent waits for the real Dart initProvider readiness handshake, exactly once.
  plugin.queueCardAction(true)
  plugin.queueCardAction(false)
  assert.equal(commands.length, 0)
  plugin.onMethodCall({ method: 'vpnCardReady', args: true }, result)
  assert.deepEqual(commands, [{ method: 'vpnCardToggle', data: true }])
  assert.equal(updates.at(-1).data.vpnStatus, 'starting')
  plugin.requestCardAction(false)
  assert.equal(commands.length, 1, 'repeated taps must not queue an opposite action')
  plugin.onMethodCall({ method: 'vpnCardComplete', args: 'failed' }, result)
  assert.equal(updates.at(-1).data.vpnStatus, 'failed')
  plugin.refreshCard()
  await settle()
  assert.equal(updates.at(-1).data.vpnStatus, 'stopped')
  assert.equal(state.runState, 'stop')
  entry.handleGetRunTime = async () => 12345
  plugin.refreshCard()
  await settle()
  assert.equal(updates.at(-1).data.vpnStatus, 'connected')
  assert.equal(state.runState, 'start')
  state.runState = 'pending'
  plugin.refreshCard()
  await settle()
  assert.equal(state.runState, 'pending', 'a status query must preserve an active operation')
  state.runState = 'stop'
  plugin.onMethodCall({ method: 'vpnCardReady', args: false }, result)
  plugin.requestCardAction(true)
  assert.equal(commands.length, 1)
  assert.equal(updates.at(-1).data.controlReady, false)
  assert.equal(updates.at(-1).data.vpnStatus, 'unknown')

  // Standard startup/stop callbacks are the authority for every card; failures never look connected.
  let startCallback
  entry.handleStartService = async (_options, _time, stub) => { startCallback = stub }
  plugin.onMethodCall({ method: 'start' }, result)
  assert.equal(updates.at(-1).data.vpnStatus, 'starting')
  startCallback.onResult(0, 'VPN start failed')
  assert.equal(updates.at(-1).data.vpnStatus, 'failed')
  assert.equal(state.runState, 'stop')
  entry.handleStopService = async (stub) => { stub.onResult(0, '') }
  state.runState = 'start'
  plugin.onMethodCall({ method: 'stop' }, result)
  await settle()
  assert.equal(updates.at(-1).data.vpnStatus, 'stopped')

  // An older status RPC must not erase the newer in-progress command.
  const racePlugin = new subject.ServicePlugin(entry)
  racePlugin.onAttachedToEngine({ getBinaryMessenger() {} })
  entry.handleGetRunTime = async () => 0
  racePlugin.onMethodCall({ method: 'vpnCardReady', args: true }, result)
  await settle()
  let finishOldQuery
  entry.handleGetRunTime = () => new Promise((resolve) => { finishOldQuery = resolve })
  racePlugin.refreshCard()
  racePlugin.requestCardAction(true)
  finishOldQuery(99999)
  await settle()
  assert.equal(updates.at(-1).data.vpnStatus, 'starting')
  racePlugin.onDetachedFromEngine({})
  assert.equal(updates.at(-1).data.controlReady, false)
  assert.equal(updates.at(-1).data.vpnStatus, 'unknown')

  // Existing small card and every native-language resource keep the new controls discoverable.
  const card = fs.readFileSync(path.join(root, 'widget/pages/WidgetCard.ets'), 'utf8')
  assert.ok(!card.includes("abilityName: 'TempAbility'"), 'do not reacquire TempAbility IPC lock')
  assert.match(card, /method: 'vpnCardToggle'/)
  assert.match(card, /\.enabled\(!this\.busy\(\)\)/)
  assert.match(card, /\.onClick\(\(\) => this\.open\(\)\)/)
  for (const locale of ['base', 'en', 'zh_CN', 'ja', 'ru']) {
    const resources = JSON.parse(fs.readFileSync(path.join(root, `../resources/${locale}/element/string.json`), 'utf8'))
    for (const key of [...card.matchAll(/app\.string\.(widget_\w+)/g)].map((match) => match[1])) {
      assert.ok(resources.string.some((entry) => entry.name === key && entry.value), `${locale} missing ${key}`)
    }
  }
  console.log('VPN card actual-source checks passed')
}
main().catch((error) => { console.error(error); process.exitCode = 1 })

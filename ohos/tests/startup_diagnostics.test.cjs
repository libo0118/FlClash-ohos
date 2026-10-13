// Executes the production ArkTS logic with mocked Harmony APIs; CI still checks ArkTS compilation.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const { stripTypeScriptTypes } = require('node:module')

class Sequence {
  values = []
  writeLong(value) { this.values.push(value) }
  writeString(value) { this.values.push(value) }
  writeInt(value) { this.values.push(value) }
  writeBoolean(value) { this.values.push(value) }
  writeByteArray(value) { this.values.push(value) }
  readLong() { return this.values.shift() }
  readString() { return this.values.shift() }
  readInt() { return this.values.shift() }
  readBoolean() { return this.values.shift() }
  readByteArray() { return this.values.shift() }
  reclaim() {}
}
const clock = { now: 1700000000000, nextId: 0, timers: new Map() }
function schedule(callback, delay, interval = false) {
  const id = ++clock.nextId
  clock.timers.set(id, { callback, due: clock.now + delay, interval: interval ? delay : 0 })
  return id
}
async function settle() { await new Promise(setImmediate) }
async function advance(ms) {
  const end = clock.now + ms
  for (;;) {
    const next = [...clock.timers].filter(([, timer]) => timer.due <= end).sort((a, b) => a[1].due - b[1].due)[0]
    if (!next) break
    const [id, timer] = next
    clock.now = timer.due
    if (timer.interval) timer.due += timer.interval
    else clock.timers.delete(id)
    timer.callback()
    await settle()
  }
  clock.now = end
  await settle()
}
function intervalCount() { return [...clock.timers.values()].filter((timer) => timer.interval).length }
const native = {}
const consoleLines = []
const state = { runTime: 0, runState: 'stop', state: undefined }
let coreListener
const context = vm.createContext({
  easyTier: native,
  rpc: { RemoteObject: class {}, MessageOption: class { setAsync() {} }, MessageSequence: { create: () => new Sequence() } },
  VpnExtensionAbility: class {}, FlutterAbility: class {},
  VpnOptions: class {},
  globalState: state, RunState: { stop: 'stop', start: 'start', pending: 'pending' },
  deviceInfo: { sdkApiVersion: 23 },
  util: { TextEncoder: { create: () => ({ encodeInto: (text) => new TextEncoder().encode(text) }) }, TextDecoder: { create: () => ({ decodeToString: (bytes) => new TextDecoder().decode(bytes) }) } },
  Date: class extends Date { constructor(value = clock.now) { super(value) } static now() { return clock.now } },
  console: { error: (line) => consoleLines.push(line) },
  setTimeout: (callback, delay) => schedule(callback, delay), clearTimeout: (id) => clock.timers.delete(id),
  setInterval: (callback, delay) => schedule(callback, delay, true), clearInterval: (id) => clock.timers.delete(id),
  setEventListener: (callback) => { coreListener = callback },
  invokeAction: (callback, data) => callback(data), quickSetup: (callback, _init, data) => callback(data),
  startTUN() {}, stopTun() {}, suspend() {}, updateDns() {},
})
const root = path.join(__dirname, '../entry/src/main/ets')
for (const file of ['utils/Rpc.ets', 'managers/EasyTierManager.ets', 'entryability/EntryAbility.ets', 'extensionAbility/VpnExtAbility.ets', 'plugins/ServicePlugin.ets']) {
  let source = fs.readFileSync(path.join(root, file), 'utf8')
  source = source.replace(/^import[\s\S]*?from\s+['"][^'"]+['"];?[^\S\r\n]*\r?\n/gm, '')
  source = source.replace(/\bexport default /g, '').replace(/\bexport /g, '')
  vm.runInContext(stripTypeScriptTypes(source, { mode: 'transform' }), context, { filename: file })
}
vm.runInContext('globalThis.subject = { EasyTierManager, VpnExtAbility, CallbackStub, ResultStub, ServicePlugin, sanitizeStartupMessage, startupErrorMessage }', context)
const subject = context.subject
const secret = '测试"密钥\\\n值'
const escaped = JSON.stringify(secret).slice(1, -1)
function error(message, code) { return Object.assign(new Error(message), { code }) }
function resetNative() {
  Object.assign(native, {
    drainLogLines: () => [], initConfigStore: () => true, enableSocketProtection: () => true,
    initTracingSubscriber() {}, configureLogManager() {},
    nextSocketProtectionRequest: async () => null, completeSocketProtection() {}, failSocketProtection() {},
    disableSocketProtection() {}, runEmbeddedNetworkInstance: () => true, stopEmbeddedNetworkInstance: () => true,
    collectRuntimeStateJson: () => JSON.stringify({ instances: [] }),
  })
}
const props = { enable: true, networkName: 'test-network', networkSecret: secret, peerUrls: ['tcp://test.invalid:11010'] }
function noSecret(message) {
  assert.ok(!message.includes(secret), 'raw secret leaked')
  assert.ok(!message.includes(escaped), 'JSON escaped secret leaked')
}
function callback(stub, runTime, message) {
  const packet = new Sequence()
  packet.writeLong(runTime)
  packet.writeString(message)
  stub.onRemoteMessageRequest(0, packet, new Sequence(), {})
}
function resetState() {
  state.runTime = 0
  state.runState = 'stop'
  state.state = { vpnOptions: { easyTier: props } }
}
function resultRecorder() {
  const calls = []
  return { calls, success: (value) => calls.push({ value }), error: (code, message) => calls.push({ code, message }) }
}
function manager(logs = [], onFailure = () => {}) {
  return new subject.EasyTierManager('/private/test', onFailure, (level, message) => logs.push({ level, message }))
}
function remoteRecorder() {
  const calls = []
  const stub = new subject.CallbackStub('events', (data) => calls.push(data))
  const remote = { sendMessageRequest: async (code, packet) => {
    stub.onRemoteMessageRequest(code, packet, new Sequence(), {})
  } }
  return { remote, calls }
}
function validateEnvelope(raw) {
  const envelope = JSON.parse(raw)
  assert.equal(envelope.method, 'message')
  assert.equal(envelope.data.type, 'log')
  const row = envelope.data.data
  assert.ok(['info', 'warning', 'error', 'debug'].includes(row.LogLevel))
  assert.match(row.Payload, /^\[(EasyTier|VPN)\] /)
  assert.ok(Number.isFinite(Date.parse(row.dateTime)))
  noSecret(row.Payload)
  assert.ok(row.Payload.length <= 2400)
  return row
}

async function main() {
  const scrubbed = subject.sanitizeStartupMessage(`${secret}; ${escaped}; ${secret}`, secret)
  noSecret(scrubbed)
  assert.equal(scrubbed, '[已隐藏]; [已隐藏]; [已隐藏]')
  const platformMessage = subject.startupErrorMessage('保护阶段', error(secret, 2200001), secret)
  assert.ok(platformMessage.includes('2200001'))
  noSecret(platformMessage)

  resetNative()
  let drains = 0
  native.drainLogLines = () => ++drains === 1 ? ['stale log'] : Array.from({ length: 10 }, (_, i) => `line ${i} ${secret} ${escaped}`)
  native.initConfigStore = () => false
  const initRows = []
  const initManager = manager(initRows)
  await assert.rejects(initManager.start(props, {}), (failure) => {
    assert.ok(failure.message.includes('EasyTier 初始化配置'))
    assert.ok(!failure.message.includes('stale log'))
    assert.ok(!failure.message.includes('line 3'))
    assert.ok(failure.message.includes('line 9'))
    assert.ok(failure.message.length <= 2400)
    noSecret(failure.message)
    return true
  })
  initRows.forEach(({ message }) => noSecret(message))
  assert.ok(initRows.some(({ message }) => message.includes('EasyTier 初始化配置')))
  assert.equal(intervalCount(), 0)

  resetNative()
  drains = 0
  native.drainLogLines = () => ++drains === 1 ? [] : [`native root failure ${secret}`]
  native.runEmbeddedNetworkInstance = () => false
  native.stopEmbeddedNetworkInstance = () => { throw error(`cleanup ${escaped}`, 9001) }
  const runRows = []
  const runManager = manager(runRows)
  await assert.rejects(runManager.start(props, {}), (failure) => {
    assert.ok(failure.message.includes('EasyTier 启动内核'))
    assert.ok(failure.message.includes('native root failure'))
    assert.ok(failure.message.includes('EasyTier 清理失败'))
    assert.ok(failure.message.includes('9001'))
    noSecret(failure.message)
    return true
  })
  runRows.forEach(({ message }) => noSecret(message))
  assert.equal(intervalCount(), 0)

  resetNative()
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [{ instanceId: '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0', errorMessage: `peer rejected ${secret}` }] })
  await assert.rejects(manager().start(props, {}), (failure) => {
    assert.ok(failure.message.includes('EasyTier 等待节点连接'))
    assert.ok(failure.message.includes('peer rejected'))
    noSecret(failure.message)
    return true
  })

  resetNative()
  let protectionReply = ''
  let onFailure = 0
  native.nextSocketProtectionRequest = async () => ({ requestId: 3, socketFd: 4 })
  native.completeSocketProtection = (_id, _ok, message) => { protectionReply = message }
  const protectionRows = []
  const protectionManager = manager(protectionRows, () => { ++onFailure })
  protectionManager.active = true
  protectionManager.generation = 1
  protectionManager.networkSecret = secret
  await protectionManager.protectSockets({ protect: async () => { throw error(`denied ${secret}`, 2200002) } }, 1)
  assert.equal(onFailure, 1)
  assert.ok(protectionReply.includes('2200002'))
  noSecret(protectionReply)
  noSecret(protectionManager.failure.message)
  protectionRows.forEach(({ message }) => noSecret(message))

  // Run the real pending lifecycle while the one native-log reader drains a destructive ring.
  resetNative()
  const liveVpn = new subject.VpnExtAbility()
  liveVpn.networkSecret = secret
  const liveRemote = remoteRecorder()
  liveVpn.handleSetEventListener(liveRemote.remote)
  const liveManager = new subject.EasyTierManager('/private/test', () => {}, (level, message) => {
    liveVpn.recordDiagnostic('EasyTier', level, message)
  })
  let releaseProtection
  native.nextSocketProtectionRequest = () => new Promise((resolve) => { releaseProtection = resolve })
  native.failSocketProtection = () => releaseProtection?.(null)
  let ring = ['4[Rust:old] stale session']
  let tracingInitialized = false
  native.initTracingSubscriber = () => { tracingInitialized = true }
  native.configureLogManager = (core, debug) => {
    assert.equal(tracingInitialized, true)
    assert.equal(core, true)
    assert.equal(debug, false)
  }
  native.drainLogLines = () => ring.splice(0)
  const instance = { instanceId: '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0', running: true, errorMessage: null, myNodeInfo: { virtualIpv4: null }, peers: [] }
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [instance] })
  let finished = false
  const pendingStart = liveManager.start(props, {}).then(() => { finished = true }, (failure) => { finished = true; return failure })
  await settle()
  assert.equal(finished, false)
  assert.ok(liveRemote.calls.map(validateEnvelope).some((row) => row.Payload.includes('EasyTier 等待节点连接')))
  assert.ok(!liveRemote.calls.some((raw) => raw.includes('stale session')))
  assert.equal(intervalCount(), 1)
  // Formats/levels come from easytier-ohrs native_log.rs, lib.rs macros and log_manager.rs::format_line.
  ring.push(`4[Rust:node] connected ${secret}`, `6[Rust:peer] retry ${escaped}`, `5[Rust:peer] failed ${secret}`, '3[Rust:debug] detail', '2[Rust:trace] detail', `4[RustOhrs] [Rust] initialized ${escaped}`, `5[RustOhrs] [Rust] start_kernel failed ${secret}`)
  await advance(1000)
  const nativeRows = liveRemote.calls.map(validateEnvelope).filter((row) => row.Payload.includes('[Rust'))
  assert.deepEqual(nativeRows.map((row) => row.LogLevel), ['info', 'warning', 'error', 'debug', 'debug', 'info', 'error'])
  assert.equal(ring.length, 0)
  await advance(4000)
  assert.equal(liveRemote.calls.map(validateEnvelope).filter((row) => row.Payload.includes('连接状态')).length, 2)
  instance.errorMessage = `peer rejected ${escaped}`
  await advance(250)
  const liveFailure = await pendingStart
  assert.ok(liveFailure.message.includes('[Rust:peer] failed'))
  noSecret(liveFailure.message)
  assert.equal(intervalCount(), 0)
  assert.ok(liveRemote.calls.map(validateEnvelope).some((row) => row.Payload.includes('清理完成')))
  const logCountAfterCleanup = liveRemote.calls.length
  await advance(1000)
  assert.equal(liveRemote.calls.length, logCountAfterCleanup)

  // Successful readiness and cancellation keep the same network lifecycle, with no timer left behind.
  resetNative()
  native.nextSocketProtectionRequest = () => new Promise((resolve) => { releaseProtection = resolve })
  native.failSocketProtection = () => releaseProtection?.(null)
  const ready = { ...instance, errorMessage: null, myNodeInfo: { virtualIpv4: '10.144.144.2' }, peers: [{ conns: [{ isClosed: false }] }] }
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [ready] })
  const successRows = []
  const successManager = manager(successRows)
  await successManager.start(props, {})
  assert.ok(successRows.some(({ message }) => message.includes('启动完成')))
  assert.equal(intervalCount(), 1)
  await successManager.stop()
  assert.equal(intervalCount(), 0)
  const canceledManager = manager()
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [] })
  const canceledStart = canceledManager.start(props, {}).catch((failure) => failure)
  await settle()
  canceledManager.cancel()
  assert.equal(intervalCount(), 0)
  await advance(250)
  assert.match((await canceledStart).message, /启动已取消/)

  // Missing listeners retain a bounded backlog; the actual RPC chunk reader receives its ABI intact.
  const queuedVpn = new subject.VpnExtAbility()
  queuedVpn.networkSecret = secret
  for (let i = 0; i < 150; ++i) queuedVpn.recordDiagnostic('VPN', 'info', `entry ${i} ${secret} ${escaped}`)
  assert.equal(queuedVpn.diagnosticBacklog.length, 100)
  const queuedRemote = remoteRecorder()
  queuedVpn.handleSetEventListener(queuedRemote.remote)
  await settle()
  assert.equal(queuedRemote.calls.length, 100)
  assert.equal(queuedVpn.diagnosticBacklog.length, 0)
  const queuedRows = queuedRemote.calls.map(validateEnvelope)
  assert.ok(queuedRows[0].Payload.includes('entry 50 '))
  assert.ok(queuedRows[99].Payload.includes('entry 149 '))
  const coreRaw = JSON.stringify({ method: 'message', data: { type: 'log', data: { LogLevel: 'info', Payload: 'legacy core event', dateTime: new Date().toISOString() } } })
  coreListener(coreRaw)
  await settle()
  assert.equal(queuedRemote.calls.at(-1), coreRaw)
  const actionRemote = remoteRecorder()
  queuedVpn.handleInvokeAction('legacy action response', actionRemote.remote)
  queuedVpn.handleQuickSetup('init', 'legacy quick setup response', actionRemote.remote)
  await settle()
  assert.deepEqual(actionRemote.calls, ['legacy action response', 'legacy quick setup response'])
  queuedVpn.onDisconnect({})
  assert.equal(queuedVpn.diagnosticRemote, undefined)
  assert.equal(coreListener, undefined)
  queuedVpn.recordDiagnostic('VPN', 'info', 'after disconnect')
  assert.equal(queuedVpn.diagnosticBacklog.length, 1)
  const failingRemote = { sendMessageRequest: async () => { throw error('listener disconnected', 1) } }
  queuedVpn.handleSetEventListener(failingRemote)
  await settle()
  assert.equal(queuedVpn.diagnosticRemote, undefined)
  assert.equal(queuedVpn.diagnosticBacklog.length, 1)

  resetState()
  const vpn = new subject.VpnExtAbility()
  const vpnRemote = remoteRecorder()
  vpn.handleSetEventListener(vpnRemote.remote)
  vpn.vpnConnection = { destroy: async () => {}, create: async () => { throw error(`create ${secret}`, 2200003) } }
  const options = { enable: true, port: 7890, routeAddress: [], ipv6: false, allowBypass: false, accessControlProps: { enable: false }, easyTier: props }
  state.state.vpnOptions = options
  const plugin = new subject.ServicePlugin({ handleStartService: (_options, time, stub) => {
    vpn.handleStartService(options, time, { sendMessageRequest: async (_code, packet) => {
      stub.onRemoteMessageRequest(0, packet, new Sequence(), {})
    } })
    return Promise.resolve()
  } })
  const result = resultRecorder()
  plugin.handleStart(result)
  await vpn.operation
  assert.equal(result.calls.length, 1)
  assert.equal(result.calls[0].code, 'VPN_START_FAILED')
  assert.ok(result.calls[0].message.includes('VPN 创建连接'))
  assert.ok(result.calls[0].message.includes('2200003'))
  noSecret(result.calls[0].message)
  assert.equal(state.runTime, 0)
  consoleLines.forEach(noSecret)
  await settle()
  const vpnRows = vpnRemote.calls.map(validateEnvelope)
  assert.ok(vpnRows.some((row) => row.Payload.includes('VPN 创建连接')))
  assert.ok(vpnRows.some((row) => row.LogLevel === 'error' && row.Payload.includes('2200003')))

  resetState()
  const raceResult = resultRecorder()
  new subject.ServicePlugin({ handleStartService: (_options, _time, stub) => {
    callback(stub, 123, '')
    callback(stub, 0, 'late callback')
    return Promise.reject(error('late request rejection', 5))
  } }).handleStart(raceResult)
  await Promise.resolve()
  await Promise.resolve()
  assert.equal(raceResult.calls.length, 1)
  assert.equal(raceResult.calls[0].value, true)
  assert.equal(state.runTime, 123)

  resetState()
  const requestResult = resultRecorder()
  let lateStub
  new subject.ServicePlugin({ handleStartService: (_options, _time, stub) => {
    lateStub = stub
    return Promise.reject(error(`request ${escaped}`, 2200004))
  } }).handleStart(requestResult)
  await Promise.resolve()
  callback(lateStub, 123, '')
  assert.equal(requestResult.calls.length, 1)
  assert.equal(requestResult.calls[0].code, 'VPN_START_FAILED')
  assert.ok(requestResult.calls[0].message.includes('VPN 启动请求'))
  assert.ok(requestResult.calls[0].message.includes('2200004'))
  noSecret(requestResult.calls[0].message)
  assert.equal(state.runTime, 0)
  assert.equal(intervalCount(), 0)
  assert.equal(clock.timers.size, 0)
  console.log('PASS: live startup/native logs, pending visibility, severity ABI, bounded RPC backlog, secret redaction, retained failure tail, timer cleanup, legacy callbacks and RPC races')
}
main().catch((failure) => { console.error(failure); process.exitCode = 1 })

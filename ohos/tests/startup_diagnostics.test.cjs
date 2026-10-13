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
let nextRouteSession = 0
const context = vm.createContext({
  easyTier: native,
  rpc: { RemoteObject: class {}, MessageOption: class { setAsync() {} }, MessageSequence: { create: () => new Sequence() } },
  VpnExtensionAbility: class {}, FlutterAbility: class {},
  VpnOptions: class {},
  globalState: state, RunState: { stop: 'stop', start: 'start', pending: 'pending' },
  deviceInfo: { sdkApiVersion: 23 },
  util: { generateRandomUUID: () => `test-session-${++nextRouteSession}`, TextEncoder: { create: () => ({ encodeInto: (text) => new TextEncoder().encode(text) }) }, TextDecoder: { create: () => ({ decodeToString: (bytes) => new TextDecoder().decode(bytes) }) } },
  Date: class extends Date { constructor(value = clock.now) { super(value) } static now() { return clock.now } },
  console: { error: (line) => consoleLines.push(line) },
  setTimeout: (callback, delay) => schedule(callback, delay), clearTimeout: (id) => clock.timers.delete(id),
  setInterval: (callback, delay) => schedule(callback, delay, true), clearInterval: (id) => clock.timers.delete(id),
  setEventListener: (callback) => { coreListener = callback },
  invokeAction: (callback, data) => callback(data), quickSetup: (callback, _init, data) => callback(data),
  startTUN() {}, stopTun() {}, suspend() {}, updateDns() {},
})
const root = path.join(__dirname, '../entry/src/main/ets')
for (const file of ['utils/Rpc.ets', 'managers/EasyTierManager.ets', 'managers/VpnCardManager.ets', 'entryability/EntryAbility.ets', 'extensionAbility/VpnExtAbility.ets', 'plugins/ServicePlugin.ets']) {
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
function manager(logs = [], onFailure = () => {}, routes = []) {
  return new subject.EasyTierManager('/private/test', onFailure, (level, message) => logs.push({ level, message }), (snapshot) => routes.push(JSON.parse(JSON.stringify(snapshot))))
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
function logRows(calls) { return calls.filter((raw) => JSON.parse(raw).data.type === 'log').map(validateEnvelope) }
function routeEvents(calls) {
  return calls.map((raw) => JSON.parse(raw)).filter((envelope) => envelope.data.type === 'easyTierRoutes').map((envelope) => {
    assert.equal(envelope.method, 'message')
    const snapshot = envelope.data.data
    assert.equal(typeof snapshot.sessionId, 'string')
    assert.ok(snapshot.sessionId.length > 0)
    assert.ok(Number.isInteger(snapshot.revision) && snapshot.revision > 0)
    assert.ok(['starting', 'ready', 'stopped'].includes(snapshot.status))
    assert.ok(Array.isArray(snapshot.cidrs) && snapshot.cidrs.every((cidr) => typeof cidr === 'string'))
    assert.ok(['starting', 'ready', 'stopped', 'unavailable'].includes(snapshot.peerStatus))
    assert.ok(Number.isInteger(snapshot.capturedAt) && snapshot.capturedAt > 0)
    assert.ok(snapshot.virtualIpv4 === null || typeof snapshot.virtualIpv4 === 'string')
    assert.ok(Array.isArray(snapshot.peers) && snapshot.peers.length <= 512)
    for (const peer of snapshot.peers) {
      assert.match(peer.peerId, /^\d+$/)
      assert.ok(typeof peer.hostname === 'string' && peer.hostname.length <= 128)
      assert.ok(peer.ipv4 === null || typeof peer.ipv4 === 'string')
      assert.ok(['direct', 'relay'].includes(peer.connectionType))
      assert.ok(peer.latencyMs === null || Number.isFinite(peer.latencyMs) && peer.latencyMs > 0)
      assert.ok(Array.isArray(peer.protocols) && peer.protocols.length <= 9)
    }
    noSecret(JSON.stringify(snapshot))
    return snapshot
  })
}
function routeSnapshot(sessionId, revision, status, cidrs) {
  return { sessionId, configTag: '', revision, status, cidrs, peerStatus: status === 'ready' ? 'unavailable' : status, virtualIpv4: null, peers: [], capturedAt: clock.now }
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
  }, (snapshot) => liveVpn.recordRoutes(snapshot))
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
  const instance = { instanceId: '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0', running: true, errorMessage: null, myNodeInfo: { virtualIpv4: null, virtualIpv4Cidr: null, peerId: null }, peers: [], routes: [] }
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [instance] })
  let finished = false
  const pendingStart = liveManager.start(props, {}).then(() => { finished = true }, (failure) => { finished = true; return failure })
  await settle()
  assert.equal(finished, false)
  assert.ok(logRows(liveRemote.calls).some((row) => row.Payload.includes('EasyTier 等待节点连接')))
  assert.ok(!liveRemote.calls.some((raw) => raw.includes('stale session')))
  assert.equal(intervalCount(), 1)
  // Formats/levels come from easytier-ohrs native_log.rs, lib.rs macros and log_manager.rs::format_line.
  ring.push(`4[Rust:node] connected ${secret}`, `6[Rust:peer] retry ${escaped}`, `5[Rust:peer] failed ${secret}`, '3[Rust:debug] detail', '2[Rust:trace] detail', `4[RustOhrs] [Rust] initialized ${escaped}`, `5[RustOhrs] [Rust] start_kernel failed ${secret}`)
  await advance(1000)
  const nativeRows = logRows(liveRemote.calls).filter((row) => row.Payload.includes('[Rust'))
  assert.ok(nativeRows.every((row) => row.Payload.startsWith('[EasyTier] [Core] ')), 'background Rust logs have a separate notification-policy marker')
  assert.deepEqual(nativeRows.map((row) => row.LogLevel), ['info', 'warning', 'error', 'debug', 'debug', 'info', 'error'])
  assert.equal(ring.length, 0)
  await advance(4000)
  assert.equal(logRows(liveRemote.calls).filter((row) => row.Payload.includes('连接状态')).length, 2)
  assert.equal(routeEvents(liveRemote.calls).at(-1).peerStatus, 'starting')
  assert.equal(routeEvents(liveRemote.calls).at(-1).capturedAt, clock.now, 'existing startup progress supplies a heartbeat')
  instance.errorMessage = `peer rejected ${escaped}`
  await advance(250)
  const liveFailure = await pendingStart
  assert.ok(liveFailure.message.includes('[Rust:peer] failed'))
  noSecret(liveFailure.message)
  assert.equal(intervalCount(), 0)
  assert.ok(logRows(liveRemote.calls).some((row) => row.Payload.includes('清理完成')))
  const logCountAfterCleanup = liveRemote.calls.length
  await advance(1000)
  assert.equal(liveRemote.calls.length, logCountAfterCleanup)

  // Successful readiness and cancellation keep the same network lifecycle, with no timer left behind.
  resetNative()
  native.nextSocketProtectionRequest = () => new Promise((resolve) => { releaseProtection = resolve })
  native.failSocketProtection = () => releaseProtection?.(null)
  const ready = { ...instance, errorMessage: null, myNodeInfo: { virtualIpv4: '10.144.144.2', virtualIpv4Cidr: '10.144.144.2/24', peerId: 23 }, peers: [{ peerId: 7, conns: [{ peerId: 7, isClosed: false, tunnelType: 'tcp', stats: { latencyUs: 12500 } }] }] }
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [ready] })
  const successRows = []
  const successManager = manager(successRows)
  let launchedConfig
  native.runEmbeddedNetworkInstance = (config) => { launchedConfig = JSON.parse(config); return true }
  await successManager.start(props, {})
  assert.equal(launchedConfig.disable_ipv6, true, 'old settings retain IPv4-only transport')
  assert.ok(successRows.some(({ message }) => message.includes('启动完成')))
  assert.equal(intervalCount(), 1)
  await successManager.stop()
  assert.equal(intervalCount(), 0)
  await successManager.start({ ...props, ipv6: true }, {})
  assert.equal(launchedConfig.disable_ipv6, false, 'independent EasyTier IPv6 toggle reaches the core')
  assert.equal(launchedConfig.no_tun, true)
  assert.deepEqual(launchedConfig.listener_urls, [])
  await successManager.stop()
  await successManager.start({ ...props, ipv6: false }, {})
  assert.equal(launchedConfig.disable_ipv6, true, 'IPv6 can be switched back off')
  await successManager.stop()
  const canceledManager = manager()
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [] })
  const canceledStart = canceledManager.start(props, {}).catch((failure) => failure)
  await settle()
  canceledManager.cancel()
  assert.equal(intervalCount(), 0)
  await advance(250)
  assert.match((await canceledStart).message, /启动已取消/)

  // Cancellation during the initial cleanup cannot launch a new session after that cleanup finishes.
  resetNative()
  const initialStopRoutes = []
  const initialStopManager = manager([], () => {}, initialStopRoutes)
  let releaseInitialStop
  initialStopManager.pump = new Promise((resolve) => { releaseInitialStop = resolve })
  let nativeStarts = 0
  native.runEmbeddedNetworkInstance = () => { ++nativeStarts; return true }
  const initialStopStart = initialStopManager.start(props, {}).catch((failure) => failure)
  await settle()
  initialStopManager.cancel()
  releaseInitialStop()
  assert.match((await initialStopStart).message, /启动已取消/)
  assert.equal(nativeStarts, 0)
  assert.equal(initialStopRoutes.length, 0, 'a canceled cleanup must not publish a starting or ready session')
  assert.equal(intervalCount(), 0)

  // Publish full live route tables (including relayed routes), without restarting the VPN or awaiting Flutter.
  resetNative()
  native.nextSocketProtectionRequest = () => new Promise((resolve) => { releaseProtection = resolve })
  native.failSocketProtection = () => releaseProtection?.(null)
  const routeVpn = new subject.VpnExtAbility()
  const routeRemote = remoteRecorder()
  routeVpn.handleSetEventListener(routeRemote.remote)
  const routes = []
  let routeStartFinished = false
  const routeManager = new subject.EasyTierManager('/private/test', () => {}, (level, message) => {
    routeVpn.recordDiagnostic('EasyTier', level, message)
  }, (snapshot) => {
    if (snapshot.status === 'ready' && routes.length === 1) assert.equal(routeStartFinished, false)
    routes.push(JSON.parse(JSON.stringify(snapshot)))
    routeVpn.recordRoutes(snapshot)
  })
  const routeInstance = {
    ...ready,
    myNodeInfo: { virtualIpv4: '10.126.126.2', virtualIpv4Cidr: '10.126.126.2/24', peerId: 23 },
    peers: [
      { peerId: 7, conns: [
        { peerId: 7, isClosed: false, tunnelType: 'tcp', stats: { latencyUs: 12500 }, remoteAddr: 'tcp://wrong.invalid:11010', localAddr: 'tcp://192.168.6.159:45000', resolvedRemoteAddr: 'tcp://user:private@192.168.6.183:11010/?token=hidden' },
        { peerId: 7, isClosed: false, tunnelType: 'udp', stats: { latencyUs: 20000 } },
        { peerId: 7, isClosed: true, tunnelType: 'quic', stats: { latencyUs: 1 } },
      ] },
      { peerId: 8, conns: [{ peerId: 8, isClosed: true, tunnelType: 'tcp', stats: { latencyUs: 2 } }] },
      { peerId: 9, conns: [{ peerId: 9, isClosed: false, tunnelType: secret, stats: null }] },
      { peerId: 99, conns: [{ peerId: 99, isClosed: false, tunnelType: 'tcp', stats: { latencyUs: 1000 } }] },
    ],
    routes: [
      { peerId: 7, cost: 1, hostname: 'workstation', ipv4: '10.126.126.7', ipv4Cidr: '10.126.126.7/32', proxyCidrs: ['192.168.6.0/24', '2001:db8::/64'] },
      { peerId: 8, hostname: 'relayed-node', ipv4: '10.126.126.8', ipv4Cidr: null, proxyCidrs: ['192.168.6.0/24'], nextHopPeerId: 7, cost: 2, pathLatency: 1000 },
      { peerId: 9, cost: 1, hostname: 'no-measurement', ipv4: null, ipv4Cidr: null, proxyCidrs: [] },
      { peerId: 23, hostname: 'self', ipv4: '10.126.126.2', ipv4Cidr: '10.126.126.2/24', proxyCidrs: [] },
    ],
  }
  let routeQueryError = false
  let rawOverride = null
  native.collectRuntimeStateJson = () => {
    if (routeQueryError) throw error('transient query failure', 1)
    if (rawOverride !== null) return rawOverride
    return JSON.stringify({ instances: [routeInstance] })
  }
  await routeManager.start(props, {}, 'test-config-tag').then(() => { routeStartFinished = true })
  await settle()
  assert.deepEqual(routes.map(({ status, revision }) => [status, revision]), [['starting', 1], ['ready', 2]])
  assert.ok(routes.every(({ configTag }) => configTag === 'test-config-tag'))
  assert.deepEqual(routes[1].cidrs, ['10.126.126.2/24', '10.126.126.7/32', '10.126.126.8/32', '192.168.6.0/24'])
  assert.equal(routes[0].peerStatus, 'starting')
  assert.equal(routes[0].virtualIpv4, null)
  assert.deepEqual(routes[0].peers, [])
  assert.equal(routes[1].peerStatus, 'ready')
  assert.equal(routes[1].virtualIpv4, '10.126.126.2')
  assert.deepEqual(routes[1].peers, [
    { peerId: '7', hostname: 'workstation', ipv4: '10.126.126.7', connectionType: 'direct', latencyMs: 12.5, protocols: ['tcp', 'udp'], connections: ['TCP 192.168.6.159:45000 → 192.168.6.183:11010'] },
    { peerId: '8', hostname: 'relayed-node', ipv4: '10.126.126.8', connectionType: 'relay', latencyMs: null, protocols: [], connections: [] },
    { peerId: '9', hostname: 'no-measurement', ipv4: null, connectionType: 'direct', latencyMs: null, protocols: [], connections: [] },
  ], 'route-known peers exclude self and unrelated relay, and only direct target RTT is measured')
  assert.equal(routeManager.socketAddress('tcp://[2001:db8::1]:11010/?token=hidden'), '[2001:db8::1]:11010')
  assert.equal(routeManager.socketAddress('tcp://wrong.invalid:11010'), null)
  assert.equal(routeManager.socketAddress('tcp://192.168.1.1:70000'), null)
  assert.deepEqual(routeEvents(routeRemote.calls), [routes[1]], 'full snapshots may coalesce while an earlier log RPC is in flight')
  assert.equal(intervalCount(), 1)
  const initialCidrs = routes[1].cidrs
  const routeLogCount = () => logRows(routeRemote.calls).filter((row) => row.Payload.includes('自动路由快照已更新')).length
  assert.equal(routeLogCount(), 1)
  await advance(4000)
  assert.equal(routes.length, 4, 'same-CIDR heartbeats keep peer telemetry fresh')
  assert.deepEqual(routes.at(-1).cidrs, initialCidrs)
  assert.equal(routes.at(-1).capturedAt, clock.now)
  assert.equal(routeLogCount(), 1, 'metrics heartbeats must not spam route-change logs')
  routeInstance.peers[0].conns[0].stats.latencyUs = 45000
  await advance(2000)
  assert.deepEqual(routes.at(-1).cidrs, initialCidrs)
  assert.equal(routes.at(-1).peers[0].latencyMs, 20, 'peer-only changes still publish the smallest active RTT')
  assert.equal(routeLogCount(), 1)
  routeQueryError = true
  await advance(2000)
  const assertUnavailable = () => {
    assert.equal(routes.at(-1).status, 'ready')
    assert.equal(routes.at(-1).peerStatus, 'unavailable')
    assert.equal(routes.at(-1).virtualIpv4, null)
    assert.deepEqual(routes.at(-1).peers, [])
    assert.deepEqual(routes.at(-1).cidrs, Array.from(routeManager.routeCidrs), 'telemetry failure must preserve current routing')
  }
  assertUnavailable()
  assert.deepEqual(routes.at(-1).cidrs, initialCidrs)
  routeQueryError = false
  for (const raw of ['{', JSON.stringify({ instances: [] }), ' '.repeat(2 * 1024 * 1024 + 1)]) {
    rawOverride = raw
    await advance(2000)
    assertUnavailable()
    assert.deepEqual(routes.at(-1).cidrs, initialCidrs)
  }
  rawOverride = null
  routeInstance.routes[0].proxyCidrs = ['192.168.7.0/24']
  routeInstance.routes[1].proxyCidrs = []
  await advance(2000)
  const changedCidrs = ['10.126.126.2/24', '10.126.126.7/32', '10.126.126.8/32', '192.168.7.0/24']
  assert.deepEqual(routes.at(-1).cidrs, changedCidrs)
  assert.equal(routes.at(-1).peerStatus, 'ready')
  assert.equal(routeLogCount(), 2)
  routeInstance.myNodeInfo.peerId = null
  routeInstance.routes[0].proxyCidrs = ['192.168.99.0/24']
  await advance(2000)
  assertUnavailable()
  assert.deepEqual(routes.at(-1).cidrs, changedCidrs, 'configured fallback with fabricated open peers must not be authoritative')
  routeInstance.myNodeInfo.peerId = 23
  routeInstance.routes[0].proxyCidrs = Array(4097).fill('192.168.99.0/24')
  await advance(2000)
  assertUnavailable()
  assert.deepEqual(routes.at(-1).cidrs, changedCidrs, 'oversized route snapshot must not partially withdraw routing')
  routeInstance.routes[0].proxyCidrs = ['192.168.7.0/24']
  routeInstance.peers[0].peerId = 7.5
  await advance(2000)
  assertUnavailable()
  routeInstance.peers[0].peerId = 7
  const originalRoutes = routeInstance.routes
  routeInstance.routes = Array.from({ length: 513 }, (_, index) => ({ peerId: 1000 + index, hostname: 'many', ipv4: null, ipv4Cidr: null, proxyCidrs: [] }))
  await advance(2000)
  assertUnavailable()
  assert.deepEqual(routes.at(-1).cidrs, ['10.126.126.2/24'], 'display limit must not block valid route withdrawal')
  routeInstance.routes = originalRoutes
  await advance(2000)
  assert.equal(routes.at(-1).peerStatus, 'ready')
  const invalidAddress = JSON.parse(JSON.stringify(routeInstance))
  invalidAddress.routes[0].ipv4 = '999.1.2.3'
  invalidAddress.routes[0].hostname = `${secret}\u0000${'name'.repeat(80)}`
  invalidAddress.peers[0].conns[0].stats.latencyUs = 0
  invalidAddress.peers[0].conns[1].stats.latencyUs = -1
  const parsedPeers = JSON.parse(JSON.stringify(routeManager.readPeerTelemetry(invalidAddress)))
  assert.equal(parsedPeers.peers[0].ipv4, null)
  assert.equal(parsedPeers.peers[0].latencyMs, null)
  assert.equal(parsedPeers.peers[0].hostname.length, 128)
  noSecret(JSON.stringify(parsedPeers))
  const multiHop = JSON.parse(JSON.stringify(routeInstance))
  multiHop.routes[0].cost = 2
  const viaRelay = routeManager.readPeerTelemetry(multiHop).peers[0]
  assert.equal(viaRelay.connectionType, 'relay')
  assert.equal(viaRelay.latencyMs, null)
  assert.equal(viaRelay.connections.length, 0, 'a multi-hop route must not borrow a direct-connection endpoint')
  for (let i = 1; i < routes.length; ++i) assert.equal(routes[i].revision, routes[i - 1].revision + 1)

  // The latest route snapshot survives log backlog eviction and replays to a newly attached listener.
  routeVpn.onDisconnect({})
  for (let i = 0; i < 120; ++i) routeVpn.recordDiagnostic('VPN', 'info', `route replay log ${i}`)
  const replayRemote = remoteRecorder()
  routeVpn.handleSetEventListener(replayRemote.remote)
  await settle()
  assert.deepEqual(routeEvents(replayRemote.calls), [routes.at(-1)])
  assert.equal(logRows(replayRemote.calls).length, 100)
  assert.equal(JSON.parse(replayRemote.calls[0]).data.type, 'easyTierRoutes')
  const oldTimer = [...clock.timers.values()].find((timer) => timer.interval).callback
  routeManager.cancel()
  await routeManager.stop()
  assert.equal(routes.at(-1).status, 'stopped')
  assert.equal(routes.at(-1).peerStatus, 'stopped')
  assert.equal(routes.at(-1).virtualIpv4, null)
  assert.deepEqual(routes.at(-1).peers, [])
  assert.equal(routes.filter(({ status }) => status === 'stopped').length, 1)
  const oldSession = routes[0].sessionId
  const beforeRestart = routes.length
  await routeManager.start(props, {})
  assert.deepEqual(routes.slice(beforeRestart).map(({ status, revision }) => [status, revision]), [['starting', 1], ['ready', 2]])
  assert.notEqual(routes.at(-1).sessionId, oldSession)
  oldTimer()
  assert.equal(intervalCount(), 1, 'a queued timer from the old session must not clear the new timer')
  assert.equal(routes.length, beforeRestart + 2, 'old callbacks cannot publish ready in the new session')
  await routeManager.stop()
  await settle()
  assert.equal(intervalCount(), 0)
  assert.equal(routes.at(-1).status, 'stopped')
  const deliveredRoutes = routeEvents(replayRemote.calls)
  assert.deepEqual(deliveredRoutes.at(-1), routes.at(-1))
  const deliveredRevisions = new Map()
  for (const snapshot of deliveredRoutes) {
    assert.ok(snapshot.revision > (deliveredRevisions.get(snapshot.sessionId) ?? 0), 'late sends must not restore an older revision')
    deliveredRevisions.set(snapshot.sessionId, snapshot.revision)
  }

  // A late RPC completion cannot acknowledge a newer session or a newly attached listener.
  const blockedVpn = new subject.VpnExtAbility()
  const blocked = remoteRecorder()
  let releaseSend
  const pausedRemote = { sendMessageRequest: async (code, packet) => {
    await blocked.remote.sendMessageRequest(code, packet)
    await new Promise((resolve) => { releaseSend = resolve })
  } }
  blockedVpn.handleSetEventListener(pausedRemote)
  blockedVpn.recordRoutes(routeSnapshot('old', 1, 'ready', ['10.1.0.0/24']))
  await settle()
  blockedVpn.recordRoutes(routeSnapshot('old', 2, 'stopped', []))
  const newSnapshot = routeSnapshot('new', 1, 'starting', [])
  blockedVpn.recordRoutes(newSnapshot)
  const replacementRemote = remoteRecorder()
  blockedVpn.handleSetEventListener(replacementRemote.remote)
  releaseSend()
  await settle()
  assert.deepEqual(routeEvents(blocked.calls).map(({ sessionId }) => sessionId), ['old'])
  assert.deepEqual(routeEvents(replacementRemote.calls), [newSnapshot])

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
  const customRouteAddress = ['192.168.50.0/24', '2001:db8::/64']
  const customRouteOptions = { ...options, routeAddress: customRouteAddress, ipv6: true }
  const toCidrs = (config) => Array.from(config.routes, ({ destination }) => `${destination.address.address}/${destination.prefixLength}`)
  assert.deepEqual(toCidrs(vpn.toVpnConfig(customRouteOptions)), ['0.0.0.0/0', '2001:db8::/64'], 'learned IPv4 routes must always reach the existing TUN')
  assert.deepEqual(toCidrs(vpn.toVpnConfig({ ...customRouteOptions, easyTier: { ...props, enable: false } })), customRouteAddress, 'non-EasyTier split routes must remain unchanged')
  assert.deepEqual(customRouteAddress, ['192.168.50.0/24', '2001:db8::/64'], 'VPN config must not mutate supplied route addresses')
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
  console.log('PASS: live startup/native logs, route and peer snapshot ABI, direct RTT units, relay/closed/self filtering, same-CIDR heartbeat, transient/malformed/oversized/fallback retention, replay, initial-cleanup cancellation, full IPv4 EasyTier TUN and non-EasyTier split routes, rapid restart/timer ordering, bounded RPC backlog, redaction and legacy callbacks')
}
main().catch((failure) => { console.error(failure); process.exitCode = 1 })

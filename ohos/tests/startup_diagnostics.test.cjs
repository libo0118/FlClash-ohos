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
  readLong() { return this.values.shift() }
  readString() { return this.values.shift() }
  reclaim() {}
}
const native = {}
const consoleLines = []
const state = { runTime: 0, runState: 'stop', state: undefined }
const context = vm.createContext({
  easyTier: native,
  rpc: { RemoteObject: class {}, MessageOption: class { setAsync() {} }, MessageSequence: { create: () => new Sequence() } },
  VpnExtensionAbility: class {}, FlutterAbility: class {},
  ChunkedSender: class {}, ChunkedReader: class {},
  VpnOptions: class {},
  globalState: state, RunState: { stop: 'stop', start: 'start', pending: 'pending' },
  deviceInfo: { sdkApiVersion: 23 },
  console: { error: (line) => consoleLines.push(line) },
  setTimeout, clearTimeout, startTUN() {}, stopTun() {}, suspend() {}, updateDns() {},
})
const root = path.join(__dirname, '../entry/src/main/ets')
for (const file of ['managers/EasyTierManager.ets', 'entryability/EntryAbility.ets', 'extensionAbility/VpnExtAbility.ets', 'plugins/ServicePlugin.ets']) {
  let source = fs.readFileSync(path.join(root, file), 'utf8')
  source = source.replace(/^import[\s\S]*?from\s+['"][^'"]+['"];?[^\S\r\n]*\r?\n/gm, '')
  source = source.replace(/\bexport default /g, '').replace(/\bexport /g, '')
  vm.runInContext(stripTypeScriptTypes(source, { mode: 'transform' }), context, { filename: file })
}
vm.runInContext('globalThis.subject = { EasyTierManager, VpnExtAbility, ResultStub, ServicePlugin, sanitizeStartupMessage, startupErrorMessage }', context)
const subject = context.subject
const secret = '测试"密钥\\\n值'
const escaped = JSON.stringify(secret).slice(1, -1)
function error(message, code) { return Object.assign(new Error(message), { code }) }
function resetNative() {
  Object.assign(native, {
    drainLogLines: () => [], initConfigStore: () => true, enableSocketProtection: () => true,
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
  const initManager = new subject.EasyTierManager('/private/test', () => {})
  await assert.rejects(initManager.start(props, {}), (failure) => {
    assert.ok(failure.message.includes('EasyTier 初始化配置'))
    assert.ok(!failure.message.includes('stale log'))
    assert.ok(!failure.message.includes('line 3'))
    assert.ok(failure.message.includes('line 9'))
    assert.ok(failure.message.length <= 2400)
    noSecret(failure.message)
    return true
  })

  resetNative()
  drains = 0
  native.drainLogLines = () => ++drains === 1 ? [] : [`native root failure ${secret}`]
  native.runEmbeddedNetworkInstance = () => false
  native.stopEmbeddedNetworkInstance = () => { throw error(`cleanup ${escaped}`, 9001) }
  const runManager = new subject.EasyTierManager('/private/test', () => {})
  await assert.rejects(runManager.start(props, {}), (failure) => {
    assert.ok(failure.message.includes('EasyTier 启动内核'))
    assert.ok(failure.message.includes('native root failure'))
    assert.ok(failure.message.includes('EasyTier 清理失败'))
    assert.ok(failure.message.includes('9001'))
    noSecret(failure.message)
    return true
  })

  resetNative()
  native.collectRuntimeStateJson = () => JSON.stringify({ instances: [{ instanceId: '9d9ccb7f-71e5-4cb8-9fb1-a18d0845d6a0', errorMessage: `peer rejected ${secret}` }] })
  await assert.rejects(new subject.EasyTierManager('/private/test', () => {}).start(props, {}), (failure) => {
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
  const protectionManager = new subject.EasyTierManager('/private/test', () => { ++onFailure })
  protectionManager.active = true
  protectionManager.generation = 1
  protectionManager.networkSecret = secret
  await protectionManager.protectSockets({ protect: async () => { throw error(`denied ${secret}`, 2200002) } }, 1)
  assert.equal(onFailure, 1)
  assert.ok(protectionReply.includes('2200002'))
  noSecret(protectionReply)
  noSecret(protectionManager.failure.message)

  resetState()
  const vpn = new subject.VpnExtAbility()
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
  console.log('PASS: startup stages, native logs, secret redaction, cleanup preservation, RPC errors and completion races')
}
main().catch((failure) => { console.error(failure); process.exitCode = 1 })

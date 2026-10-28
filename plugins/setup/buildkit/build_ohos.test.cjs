const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(path.join(__dirname, 'build_ohos.cjs'), 'utf8');

function fixture(t, {
  env = {}, targets = 'openharmony/arm64\n', missing,
  metadata = 'build CGO_ENABLED=1 GOOS=openharmony GOARCH=arm64',
  elf = 'Machine: AArch64\nNEEDED [libc.so]',
  mihomoHead = 'c5062921054902b25215a6a933e72ccd714c9bfa',
  patchState = 'unpatched',
} = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-ohos-build-'));
  t.after(() => {
    assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
    fs.rmSync(root, { recursive: true, force: true });
  });
  const ndk = path.join(root, 'ndk');
  function write(relative, contents) {
    const file = path.join(root, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, contents);
  }
  if (missing !== 'compiler') write('ndk/native/llvm/bin/aarch64-unknown-linux-ohos-clang', 'clang');
  if (missing !== 'readelf') write('ndk/native/llvm/bin/llvm-readelf', 'readelf');
  if (missing !== 'bride.h') write('core/ohos/bride.h', 'bridge declarations');
  const calls = [];
  const context = {
    __dirname: path.join(root, 'plugins/setup/buildkit'),
    process: { env: { OHOS_NDK_HOME: ndk, ...env } },
    require(name) {
      if (name !== 'node:child_process') return require(name);
      return { execFileSync(command, args, options) {
        calls.push({ command, args, options });
        if (command === 'git') {
          assert.equal(options.cwd, path.join(root, 'core/Clash.Meta'));
          if (args[0] === 'rev-parse') return mihomoHead;
          assert.equal(args.at(-1), path.join(root, '.github/mihomo-ohos.patch'));
          if (args.includes('--check')) {
            const expected = args.includes('--reverse') ? 'patched' : 'unpatched';
            if (patchState !== expected) throw new Error('patch does not apply');
          } else {
            assert.equal(patchState, 'unpatched');
            patchState = 'patched';
          }
          return '';
        }
        if (command !== 'go') {
          assert.equal(command, path.join(ndk, 'native/llvm/bin/llvm-readelf'));
          assert.deepEqual(Array.from(args.slice(0, 2)), ['-h', '-d']);
          return elf;
        }
        assert.equal(command, 'go');
        assert.equal(options.env.GOTOOLCHAIN, 'local');
        if (args[0] === 'tool') return targets;
        if (args[0] === 'version') return metadata;
        assert.equal(patchState, 'patched');
        assert.equal(options.cwd, path.join(root, 'core'));
        assert.equal(options.env.GOOS, 'openharmony');
        assert.equal(options.env.GOARCH, 'arm64');
        assert.equal(options.env.CGO_ENABLED, '1');
        assert.ok(args.includes('-mod=readonly'));
        assert.ok(args.includes('-buildmode=c-shared'));
        assert.equal(args.at(-1), './ohos');
        if (missing !== 'libclash.so') write('libclash/openharmony/arm64-v8a/libclash.so', 'ELF');
        if (missing !== 'libclash.h') write('libclash/openharmony/arm64-v8a/libclash.h', 'generated declarations');
      } };
    },
  };
  return { root, calls, run: () => vm.runInNewContext(source, context) };
}

test('builds the OHOS package and distributes both headers and the shared library', (t) => {
  const value = fixture(t);
  value.run();
  assert.equal(value.calls.length, 7);
  assert.deepEqual(Array.from(value.calls[2].args.slice(0, 2)), ['apply', '--check']);
  assert.deepEqual(Array.from(value.calls[3].args.slice(0, 2)), ['apply', '--']);
  for (const prefix of ['libclash/openharmony/includes', 'ohos/core/src/main/cpp/includes']) {
    assert.equal(fs.readFileSync(path.join(value.root, prefix, 'arm64-v8a/libclash.h'), 'utf8'), 'generated declarations');
    assert.equal(fs.readFileSync(path.join(value.root, prefix, 'arm64-v8a/bride.h'), 'utf8'), 'bridge declarations');
  }
  assert.equal(fs.readFileSync(path.join(value.root, 'ohos/core/libs/arm64-v8a/libclash.so'), 'utf8'), 'ELF');
});

test('keeps an already applied mihomo patch without applying it twice', (t) => {
  const value = fixture(t, { patchState: 'patched' });
  value.run();
  const checks = value.calls.filter(({ command, args }) => command === 'git' && args[0] === 'apply');
  assert.equal(checks.length, 2);
  assert.ok(checks.every(({ args }) => args.includes('--check')));
  assert.ok(checks[1].args.includes('--reverse'));
});

for (const [name, options, error] of [
  ['missing SDK', { env: { OHOS_NDK_HOME: '' } }, /OHOS_NDK_HOME/],
  ['wrong GOOS', { env: { GOOS: 'linux' } }, /GOOS=openharmony/],
  ['wrong architecture', { env: { GOARCH: 'amd64' } }, /arm64 only/],
  ['missing compiler', { missing: 'compiler' }, /Missing OHOS compiler/],
  ['standard Go toolchain', { targets: 'linux/arm64\n' }, /does not support openharmony/],
  ['unknown mihomo revision', { mihomoHead: 'unknown' }, /does not support commit/],
  ['conflicting mihomo modifications', { patchState: 'conflict' }, /conflicts with local changes/],
  ['missing readelf', { missing: 'readelf' }, /Missing OHOS readelf/],
  ['wrong Go build target', { metadata: 'CGO_ENABLED=1 GOOS=linux GOARCH=arm64' }, /expected GOOS=openharmony/],
  ['disabled CGO', { metadata: 'CGO_ENABLED=0 GOOS=openharmony GOARCH=arm64' }, /expected CGO_ENABLED=1/],
  ['wrong Go architecture', { metadata: 'CGO_ENABLED=1 GOOS=openharmony GOARCH=amd64' }, /expected GOARCH=arm64/],
  ['wrong ELF architecture', { elf: 'Machine: X86-64' }, /incompatible architecture/],
  ['GNU Linux library', { elf: 'Machine: AArch64\nNEEDED [libc.so.6]' }, /GNU Linux dependency/],
  ...['libclash.so', 'libclash.h', 'bride.h'].map((missing) => [
    `missing ${missing}`, { missing }, /Missing OHOS core output/,
  ]),
]) {
  test(`rejects ${name}`, (t) => {
    const value = fixture(t, options);
    assert.throws(value.run, error);
    assert.equal(fs.existsSync(path.join(value.root, 'ohos/core/libs/arm64-v8a/libclash.so')), false);
  });
}

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
function ensureMihomoPatch() {
  const cwd = path.join(root, 'core/Clash.Meta');
  const options = { cwd, encoding: 'utf8', stdio: 'pipe' };
  const head = execFileSync('git', ['rev-parse', 'HEAD'], options).trim();
  if (head !== 'c5062921054902b25215a6a933e72ccd714c9bfa') {
    throw new Error(`The OHOS mihomo patch does not support commit ${head}`);
  }
  const patch = path.join(root, '.github/mihomo-ohos.patch');
  try {
    execFileSync('git', ['apply', '--check', '--', patch], options);
  } catch {
    try {
      execFileSync('git', ['apply', '--reverse', '--check', '--', patch], options);
      return;
    } catch (cause) {
      throw new Error('The OHOS mihomo patch conflicts with local changes', { cause });
    }
  }
  execFileSync('git', ['apply', '--', patch], options);
}

const ndk = process.env.OHOS_NDK_HOME;
if (!ndk) throw new Error('OHOS_NDK_HOME is required');
if (process.env.GOOS && process.env.GOOS !== 'openharmony') {
  throw new Error('The OHOS core requires GOOS=openharmony');
}
if (process.env.GOARCH && process.env.GOARCH !== 'arm64') {
  throw new Error('The OHOS app currently packages arm64 only');
}
const cc = path.join(ndk, 'native/llvm/bin/aarch64-unknown-linux-ohos-clang');
if (!fs.existsSync(cc)) throw new Error(`Missing OHOS compiler: ${cc}`);
const env = {
  ...process.env,
  GOTOOLCHAIN: 'local',
  GOOS: 'openharmony',
  GOARCH: 'arm64',
  CGO_ENABLED: '1',
  CC: cc,
};
const targets = execFileSync('go', ['tool', 'dist', 'list'], {
  env,
  encoding: 'utf8',
});
if (!targets.split(/\r?\n/).includes('openharmony/arm64')) {
  throw new Error('The local Go toolchain does not support openharmony/arm64');
}
ensureMihomoPatch();
const core = path.join(root, 'core');
const output = path.join(root, 'libclash/openharmony/arm64-v8a');
fs.mkdirSync(output, { recursive: true });
const library = path.join(output, 'libclash.so');
execFileSync('go', [
  'build', '-mod=readonly', '-tags=with_gvisor', '-ldflags=-w -s',
  '-buildmode=c-shared', '-o', library, './ohos',
], { cwd: core, env, stdio: 'inherit' });
const files = [
  [library, 'ohos/core/libs/arm64-v8a/libclash.so'],
  [path.join(output, 'libclash.h'), 'libclash/openharmony/includes/arm64-v8a/libclash.h'],
  [path.join(core, 'ohos/bride.h'), 'libclash/openharmony/includes/arm64-v8a/bride.h'],
  [path.join(output, 'libclash.h'), 'ohos/core/src/main/cpp/includes/arm64-v8a/libclash.h'],
  [path.join(core, 'ohos/bride.h'), 'ohos/core/src/main/cpp/includes/arm64-v8a/bride.h'],
];
for (const [source] of files) {
  if (!fs.existsSync(source) || fs.statSync(source).size === 0) {
    throw new Error(`Missing OHOS core output: ${source}`);
  }
}
const metadata = execFileSync('go', ['version', '-m', library], { env, encoding: 'utf8' });
for (const setting of ['CGO_ENABLED=1', 'GOOS=openharmony', 'GOARCH=arm64']) {
  if (!metadata.split(/\s+/).includes(setting)) {
    throw new Error(`Invalid OHOS Go build metadata: expected ${setting}`);
  }
}
const readelf = path.join(ndk, 'native/llvm/bin/llvm-readelf');
if (!fs.existsSync(readelf)) throw new Error(`Missing OHOS readelf: ${readelf}`);
const elf = execFileSync(readelf, ['-h', '-d', library], { encoding: 'utf8' });
if (!/Machine:\s+AArch64\b/.test(elf) ||
    /\[(?:libc\.so\.6|ld-linux-aarch64\.so\.1|libstdc\+\+\.so\.6|libpthread\.so\.0|libdl\.so\.2|libm\.so\.6|librt\.so\.1)\]/.test(elf)) {
  throw new Error('The OHOS shared library has an incompatible architecture or GNU Linux dependency');
}
console.log(metadata.trim());
console.log(elf.trim());
for (const [source, relative] of files) {
  const destination = path.join(root, relative);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

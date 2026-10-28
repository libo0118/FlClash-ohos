'use strict';

const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { test } = require('node:test');

const original = 'switch (platform) { case TargetPlatform.android: break; }\n';
const patched = original.replace('case TargetPlatform.android:', 'case TargetPlatform.ohos: case TargetPlatform.android:');
const digest = (text) => createHash('sha256').update(text).digest('hex');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ui ohos-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const write = (name, value) => {
    const target = path.join(root, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, value);
    return target;
  };
  const source = write('cache/material_ui/lib/src/widget.dart', original);
  const secondSource = write('cache/cupertino_ui/lib/src/widget.dart', original);
  const specs = [['material_ui', '1.5.0'], ['cupertino_ui', '1.1.1']];
  const packages = specs.map(([name, version]) => {
    write(`cache/${name}/pubspec.yaml`, `name: ${name}\nversion: ${version}\n`);
    return { name, version, files: [{ path: 'lib/src/widget.dart', before: digest(original), after: digest(patched), edits: [{ from: original, to: patched, count: 1 }] }] };
  });
  write('ui-ohos/manifest.json', JSON.stringify({ packages }));
  fs.copyFileSync(path.join(__dirname, 'patch-ui-ohos.cjs'), path.join(root, 'patch-ui-ohos.cjs'));
  write('.dart_tool/package_config.json', JSON.stringify({ packages: [
    ...specs.map(([name]) => ({ name, rootUri: pathToFileURL(path.join(root, 'cache', name)).href })),
    { name: 'flutter', rootUri: '../sdk/packages/flutter/' },
  ] }));
  const platform = write('sdk/packages/flutter/lib/src/foundation/platform.dart', 'enum TargetPlatform { android, iOS, ohos }');
  const { patchUi } = require(path.join(root, 'patch-ui-ohos.cjs'));
  const run = (env = {}) => patchUi({ cwd: root, env, log: () => {} });
  return { root, source, secondSource, platform, run };
}

test('OHOS apply/reapply and standard SDK reverse/reverse preserve exact original bytes', (t) => {
  const f = fixture(t);
  assert.deepEqual(f.run(), { ohos: true, changed: 2 });
  assert.equal(fs.readFileSync(f.source, 'utf8'), patched);
  assert.deepEqual(f.run(), { ohos: true, changed: 0 });
  fs.writeFileSync(f.platform, 'enum TargetPlatform { android, iOS } // ohos\n');
  assert.deepEqual(f.run({ FLUTTER_ROOT: path.join(f.root, 'sdk') }), { ohos: false, changed: 2 });
  assert.equal(fs.readFileSync(f.source, 'utf8'), original);
  assert.equal(fs.readFileSync(f.secondSource, 'utf8'), original);
  assert.deepEqual(f.run(), { ohos: false, changed: 0 });
});

test('standard SDK leaves pristine packages unchanged', (t) => {
  const f = fixture(t);
  fs.writeFileSync(f.platform, 'enum TargetPlatform { android, /* ohos, */ iOS }');
  assert.deepEqual(f.run(), { ohos: false, changed: 0 });
  assert.equal(fs.readFileSync(f.source, 'utf8'), original);
});

test('a partially applied known patch can be safely completed', (t) => {
  const f = fixture(t);
  fs.writeFileSync(f.source, patched);
  assert.deepEqual(f.run(), { ohos: true, changed: 1 });
  assert.equal(fs.readFileSync(f.source, 'utf8'), patched);
  assert.equal(fs.readFileSync(f.secondSource, 'utf8'), patched);
});

test('unknown target edits fail before mutating either package', (t) => {
  const f = fixture(t);
  fs.appendFileSync(f.secondSource, '// user change\n');
  assert.throws(() => f.run(), /Refusing unknown changes/);
  assert.equal(fs.readFileSync(f.source, 'utf8'), original);
  assert.equal(fs.readFileSync(f.secondSource, 'utf8'), original + '// user change\n');
});

test('mismatched FLUTTER_ROOT and package_config SDKs fail before patching', (t) => {
  const f = fixture(t);
  const stock = path.join(f.root, 'stock/packages/flutter/lib/src/foundation');
  fs.mkdirSync(stock, { recursive: true });
  fs.writeFileSync(path.join(stock, 'platform.dart'), 'enum TargetPlatform { android, iOS }');
  assert.throws(() => f.run({ FLUTTER_ROOT: path.join(f.root, 'stock') }), /disagree on TargetPlatform.ohos/);
  assert.equal(fs.readFileSync(f.source, 'utf8'), original);
});

test('unknown dependency versions fail before applying any edits', (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.root, 'cache/cupertino_ui/pubspec.yaml'), 'name: cupertino_ui\nversion: 1.1.2\n');
  assert.throws(() => f.run(), /Unsupported cupertino_ui version/);
  assert.equal(fs.readFileSync(f.source, 'utf8'), original);
});

test('unknown edits to patched files also prevent automatic reversal', (t) => {
  const f = fixture(t);
  f.run();
  fs.appendFileSync(f.source, '// user change\n');
  fs.writeFileSync(f.platform, 'enum TargetPlatform { android, iOS }');
  assert.throws(() => f.run(), /Refusing unknown changes/);
  assert.equal(fs.readFileSync(f.secondSource, 'utf8'), patched);
});

test('missing package metadata or invalid Flutter SDK fails explicitly', (t) => {
  const f = fixture(t);
  fs.writeFileSync(f.platform, 'const platform = "ohos";');
  assert.throws(() => f.run(), /TargetPlatform enum not found/);
  fs.writeFileSync(f.platform, 'enum TargetPlatform { android, ohos }');
  fs.writeFileSync(path.join(f.root, '.dart_tool/package_config.json'), '{"packages": []}');
  assert.throws(() => f.run({ FLUTTER_ROOT: path.join(f.root, 'sdk') }), /Expected exactly one material_ui/);
});

test('fixed manifest changes only Android alternatives, retaining nullable platform arms', () => {
  const manifest = require('./ui-ohos/manifest.json');
  assert.deepEqual(manifest.packages.map(({ name, version }) => [name, version]), [['material_ui', '1.5.0'], ['cupertino_ui', '1.1.1']]);
  for (const pkg of manifest.packages) {
    for (const file of pkg.files) {
      assert.match(file.path, /^lib\/src\/[a-z_]+\.dart$/);
      for (const edit of file.edits) {
        assert.match(edit.from, /TargetPlatform.android/);
        assert.doesNotMatch(edit.from, /TargetPlatform.ohos|null\s*=>/);
        assert.match(edit.to, /TargetPlatform.ohos/);
        const withoutOhos = edit.to
          .replace(/^\s*case TargetPlatform\.ohos:\n/gm, '')
          .replace(/^\s*TargetPlatform\.ohos: [^\n]+\n/gm, '')
          .replace(/TargetPlatform\.ohos \|\| /g, '')
          .replace('(platform == TargetPlatform.android || platform == TargetPlatform.ohos)', 'platform == TargetPlatform.android')
          .replace(' && defaultTargetPlatform != TargetPlatform.ohos', '')
          .replace(' || defaultTargetPlatform == TargetPlatform.ohos', '');
        assert.equal(withoutOhos.trimStart(), edit.from.trimStart());
      }
    }
  }
});

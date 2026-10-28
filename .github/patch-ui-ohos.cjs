#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { fileURLToPath, pathToFileURL } = require('node:url');
const manifest = require('./ui-ohos/manifest.json');

const digest = (value) => createHash('sha256').update(value).digest('hex');

function supportsOhos(flutterRoot) {
  const source = fs.readFileSync(path.join(flutterRoot, 'lib/src/foundation/platform.dart'), 'utf8');
  const platformEnum = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
    .match(/enum\s+TargetPlatform\s*\{([^}]+)\}/);
  if (!platformEnum) throw new Error(`TargetPlatform enum not found in ${flutterRoot}.`);
  return /(?:^|,)\s*ohos\s*(?:,|$)/.test(platformEnum[1]);
}

function patchUi({ cwd = process.cwd(), env = process.env, log = console.log } = {}) {
  const configPath = path.resolve(cwd, '.dart_tool/package_config.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const packageRoot = (name) => {
    const entries = config.packages.filter((entry) => entry.name === name);
    if (entries.length !== 1) throw new Error(`Expected exactly one ${name} in ${configPath}; run flutter pub get first.`);
    return fileURLToPath(new URL(entries[0].rootUri, pathToFileURL(configPath)));
  };
  const flutterRoot = env.FLUTTER_ROOT
    ? path.resolve(env.FLUTTER_ROOT, 'packages/flutter')
    : packageRoot('flutter');
  const ohos = supportsOhos(flutterRoot);
  if (env.FLUTTER_ROOT && config.packages.some((entry) => entry.name === 'flutter') &&
      supportsOhos(packageRoot('flutter')) !== ohos) {
    throw new Error('FLUTTER_ROOT and package_config Flutter disagree on TargetPlatform.ohos; rerun pub get with the intended SDK.');
  }
  const plan = [];

  for (const pkg of manifest.packages) {
    const root = packageRoot(pkg.name);
    const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
    if (!new RegExp(`^name:\\s*${pkg.name}\\s*$`, 'm').test(pubspec) ||
        !new RegExp(`^version:\\s*${pkg.version.replaceAll('.', '\\.')}\\s*$`, 'm').test(pubspec)) {
      throw new Error(`Unsupported ${pkg.name} version at ${root}; expected ${pkg.version}.`);
    }
    for (const file of pkg.files) {
      const target = path.join(root, file.path);
      const current = fs.readFileSync(target, 'utf8');
      const hash = digest(current);
      if (hash !== file.before && hash !== file.after) {
        throw new Error(`Refusing unknown changes in ${target}; restore this package with pub before applying the fixed patch.`);
      }
      if (hash === (ohos ? file.after : file.before)) continue;
      let next = current;
      for (const edit of ohos ? file.edits : [...file.edits].reverse()) {
        const from = ohos ? edit.from : edit.to;
        const to = ohos ? edit.to : edit.from;
        if (next.split(from).length - 1 !== edit.count) throw new Error(`Patch context mismatch in ${target}.`);
        next = next.split(from).join(to);
      }
      if (digest(next) !== (ohos ? file.after : file.before)) throw new Error(`Patch hash mismatch in ${target}.`);
      plan.push({ target, current, next });
    }
  }
  for (const file of plan) {
    if (fs.readFileSync(file.target, 'utf8') !== file.current) throw new Error(`File changed during patching: ${file.target}.`);
    fs.writeFileSync(file.target, file.next);
  }
  log(`UI OHOS compatibility: ${ohos ? 'applied' : 'removed'} ${plan.length} file patch(es); ${ohos ? 'OHOS' : 'standard'} Flutter SDK.`);
  return { ohos, changed: plan.length };
}

module.exports = { patchUi };

if (require.main === module) {
  try {
    patchUi();
  } catch (error) {
    console.error(`UI OHOS compatibility: ${error.message}`);
    process.exitCode = 1;
  }
}

import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {'APP_ENV': 'dev'});
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    test('pins the OHOS distributor that packages unsigned HAP and APP', () {
      expect(setup.createDistributorActivateArgs('ohos'), [
        'pub',
        'global',
        'activate',
        '-s',
        'git',
        'https://github.com/tljk/flutter_distributor.git',
        '--git-ref',
        '71966a102e6a283a14c6e953e98f9d39008efb8a',
        '--git-path',
        'packages/flutter_distributor',
      ]);
    });

    test('keeps the upstream distributor for other platforms', () {
      for (final platform in ['android', 'linux', 'macos', 'windows']) {
        expect(setup.createDistributorActivateArgs(platform), [
          'pub',
          'global',
          'activate',
          '-s',
          'git',
          'https://github.com/chen08209/flutter_distributor.git',
          '--git-ref',
          'v0.6.11-flclash.4',
          '--git-path',
          'packages/flutter_distributor',
        ], reason: platform);
      }
    });

    test('builds unsigned OHOS HAP and APP with verbose output', () {
      expect(setup.createFlutterBuildArgs(platform: 'ohos', verbose: true), [
        'verbose',
        'dart-define-from-file=env.json',
        'no-codesign',
      ]);
      expect(setup.createPackageTargets('ohos', null), 'hap,app');
    });

    test('allows only the separately built OHOS setup hook to be skipped', () {
      const pubspec = '''
hooks:
  user_defines:
    setup:
      build_assets: false
    rust_api:
      build_assets: true
''';

      expect(
        setup.packagesNotBuildingAssets(pubspec, platform: 'ohos'),
        isEmpty,
      );
      for (final platform in ['android', 'linux', 'macos', 'windows']) {
        expect(setup.packagesNotBuildingAssets(pubspec, platform: platform), [
          'setup',
        ], reason: platform);
      }
      expect(
        setup.packagesNotBuildingAssets('name: x\n', platform: 'linux'),
        isEmpty,
      );
    });

    test('OHOS still rejects disabled Rust and other native hooks', () {
      const pubspec = '''
hooks:
  user_defines:
    setup:
      build_assets: false
    rust_api:
      build_assets: false
    other_native:
      build_assets: false
''';

      expect(setup.packagesNotBuildingAssets(pubspec, platform: 'ohos'), [
        'other_native',
        'rust_api',
      ]);
    });

    test('packages every Linux format on every architecture', () {
      expect(setup.createPackageTargets('linux', null), 'deb,appimage,rpm');
      expect(setup.createPackageTargets('linux', 'deb'), 'deb');
      expect(setup.createPackageTargets('macos', null), 'dmg');
    });

    test('downloads the appimagetool build matching the host', () {
      expect(setup.appImageToolArch('arm64'), 'aarch64');
      expect(setup.appImageToolArch('amd64'), 'x86_64');
    });
  });
}

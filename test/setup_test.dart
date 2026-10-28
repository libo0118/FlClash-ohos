import 'dart:io';

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

    test('keeps the upstream distributor for other platforms', () {
      expect(setup.createDistributorActivateArgs(), [
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
      ]);
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

    group('direct OHOS packaging', () {
      late Directory root;
      File file(String path) => File('${root.path}/$path');
      String sourcePath(String format) => format == 'hap'
          ? 'ohos/entry/build/default/outputs/default/entry-default-unsigned.hap'
          : 'ohos/build/outputs/default/ohos-default-unsigned.app';
      String destinationPath(String format) =>
          'dist/FlClash-0.9.2-ohos.$format';
      Future<void> write(String path, String contents) async {
        await file(path).parent.create(recursive: true);
        await file(path).writeAsString(contents);
      }

      setUp(() async {
        root = await Directory.systemTemp.createTemp('flclash-ohos-packaging-');
        await write('pubspec.yaml', 'version: 0.9.2+2026102801\n');
        await write(
          'distribute_options.yaml',
          'app_name: FlClash\noutput: dist/\n',
        );
      });
      tearDown(() => root.delete(recursive: true));

      test(
        'awaits SDK HAP and APP builds with standard version arguments',
        () async {
          final built = <String>[];
          final exitCode = await setup.packageOhos(
            root.path,
            'hap,app',
            verbose: true,
            runCommand:
                (
                  executable,
                  arguments, {
                  required workingDirectory,
                  environment,
                }) async {
                  expect(executable, 'flutter');
                  expect(workingDirectory, root.path);
                  expect(environment, {'FLCLASH_OHOS_BUILD': '1'});
                  final format = arguments[1];
                  expect(arguments, [
                    'build',
                    format,
                    '--release',
                    '--verbose',
                    '--dart-define-from-file=env.json',
                    '--no-codesign',
                    '--build-name=0.9.2',
                    '--build-number=2026102801',
                  ]);
                  // Delayed real output catches a missing await before artifact collection.
                  await Future<void>.delayed(Duration.zero);
                  await write(sourcePath(format), 'fresh unsigned $format');
                  built.add(format);
                  return 0;
                },
          );

          expect(exitCode, 0);
          expect(built, ['hap', 'app']);
          for (final format in built) {
            expect(
              await file(destinationPath(format)).readAsString(),
              'fresh unsigned $format',
            );
          }
        },
      );

      test('supports requesting only APP without verbose output', () async {
        final exitCode = await setup.packageOhos(
          root.path,
          'app',
          verbose: false,
          runCommand:
              (
                executable,
                arguments, {
                required workingDirectory,
                environment,
              }) async {
                expect(arguments[1], 'app');
                expect(arguments, isNot(contains('--verbose')));
                await write(sourcePath('app'), 'unsigned app');
                return 0;
              },
        );

        expect(exitCode, 0);
        expect(
          await file(destinationPath('app')).readAsString(),
          'unsigned app',
        );
        expect(await file(destinationPath('hap')).exists(), isFalse);
      });

      for (final format in ['hap', 'app']) {
        for (final emptyOutput in [false, true]) {
          test(
            'rejects ${emptyOutput ? 'empty' : 'missing'} $format and ignores stale/signed/debug outputs',
            () async {
              final unsigned = sourcePath(format);
              final signed = unsigned.replaceFirst('-unsigned.', '-signed.');
              final debug = format == 'hap'
                  ? unsigned.replaceFirst(
                      '/default/outputs/',
                      '/debug/outputs/',
                    )
                  : 'ohos/build/outputs/debug/ohos-debug-unsigned.app';
              await write(unsigned, 'stale unsigned');
              await write(signed, 'signed');
              await write(debug, 'debug');
              await write(destinationPath(format), 'stale dist');

              final exitCode = await setup.packageOhos(
                root.path,
                format,
                verbose: false,
                runCommand:
                    (
                      executable,
                      arguments, {
                      required workingDirectory,
                      environment,
                    }) async {
                      expect(await file(unsigned).exists(), isFalse);
                      if (emptyOutput) await write(unsigned, '');
                      return 0;
                    },
              );

              expect(exitCode, 1);
              expect(await file(destinationPath(format)).exists(), isFalse);
              expect(await file(signed).readAsString(), 'signed');
              expect(await file(debug).readAsString(), 'debug');
            },
          );
        }
      }

      test(
        'propagates build failure and stops before APP or copying output',
        () async {
          for (final format in ['hap', 'app']) {
            await write(destinationPath(format), 'stale dist');
          }
          var commands = 0;
          final exitCode = await setup.packageOhos(
            root.path,
            'hap,app',
            verbose: false,
            runCommand:
                (
                  executable,
                  arguments, {
                  required workingDirectory,
                  environment,
                }) async {
                  commands++;
                  await write(sourcePath('hap'), 'incomplete build');
                  return 23;
                },
          );

          expect(exitCode, 23);
          expect(commands, 1);
          for (final format in ['hap', 'app']) {
            expect(await file(destinationPath(format)).exists(), isFalse);
          }
        },
      );

      test('rejects unsupported formats before running a command', () async {
        await expectLater(
          setup.packageOhos(
            root.path,
            'hap,apk',
            verbose: false,
            runCommand:
                (
                  executable,
                  arguments, {
                  required workingDirectory,
                  environment,
                }) async {
                  fail('Invalid formats must not invoke Flutter');
                },
          ),
          throwsArgumentError,
        );
      });

      test('rejects a missing build number before running Flutter', () async {
        await write('pubspec.yaml', 'version: 0.9.2\n');
        await expectLater(
          setup.packageOhos(
            root.path,
            'hap',
            verbose: false,
            runCommand:
                (
                  executable,
                  arguments, {
                  required workingDirectory,
                  environment,
                }) async {
                  fail('An invalid version must not invoke Flutter');
                },
          ),
          throwsFormatException,
        );
      });
    });
  });
}

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../hook/build.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('flclash-ohos-hook-');
  });
  tearDown(() => root.deleteSync(recursive: true));

  File compilerAt(String path) {
    return File.fromUri(root.uri.resolve(path))
      ..createSync(recursive: true)
      ..writeAsStringSync('clang');
  }

  File sdkCompiler({String name = 'clang', bool sysroot = true}) {
    final compiler = compilerAt(
      'Harmony SDK/18/openharmony/native/llvm/bin/$name',
    );
    if (sysroot) {
      Directory.fromUri(
        compiler.parent.parent.parent.uri.resolve('sysroot/'),
      ).createSync();
    }
    return compiler;
  }

  void prepareLinker(File compiler) {
    File.fromUri(
      compiler.uri.resolve('aarch64-unknown-linux-ohos-clang'),
    ).writeAsStringSync('OHOS linker wrapper');
  }

  void prepareLibclang(Directory directory) {
    directory.createSync(recursive: true);
    File.fromUri(
      directory.uri.resolve('libclang.so'),
    ).writeAsStringSync('clang');
  }

  BuildInput buildInput({
    Uri? compiler,
    OS os = OS.linux,
    Architecture architecture = Architecture.arm64,
    bool codeAssets = true,
    Map<String, Object?> userDefines = const {},
  }) {
    final builder = BuildInputBuilder()
      ..setupShared(
        packageRoot: root.uri,
        packageName: 'rust_api',
        outputDirectoryShared: root.uri.resolve('output/'),
        outputFile: root.uri.resolve('output.json'),
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: userDefines,
            basePath: root.uri,
          ),
        ),
      )
      ..setupBuildInput()
      ..config.setupBuild(linkingEnabled: false);
    if (codeAssets) {
      CodeAssetExtension(
        targetArchitecture: architecture,
        targetOS: os,
        linkModePreference: LinkModePreference.dynamic,
        cCompiler: compiler == null
            ? null
            : CCompilerConfig(
                compiler: compiler,
                archiver: compiler.resolve('llvm-ar'),
                linker: compiler.resolve('ld.lld'),
              ),
        android: os == OS.android ? AndroidCodeConfig(targetNdkApi: 23) : null,
      ).setupBuildInput(builder);
    }
    return builder.build();
  }

  test('accepts OHOS ELF and rejects host or GNU Linux libraries', () {
    checkOhosElf(
      'Machine: AArch64\nNEEDED [libc.so]\nNEEDED [libc++_shared.so]',
    );
    expect(() => checkOhosElf('Machine: X86-64'), throwsStateError);
    for (final library in [
      'libc.so.6',
      'ld-linux-aarch64.so.1',
      'libstdc++.so.6',
    ]) {
      expect(
        () => checkOhosElf('Machine: AArch64\nNEEDED [$library]'),
        throwsStateError,
      );
    }
  });
  test('recognizes the SDK clang and clang.exe without OHOS environment', () {
    expect(isOhosCompiler(sdkCompiler().uri), isTrue);
    expect(isOhosCompiler(sdkCompiler(name: 'clang.exe').uri), isTrue);
    expect(isOhosCompiler(null), isFalse);
  });

  test(
    'keeps Android and ordinary host compilers on the native builder',
    () async {
      for (final (os, path) in [
        (OS.linux, 'usr/bin/clang'),
        (OS.windows, 'Visual Studio/bin/cl.exe'),
        (OS.macOS, 'Xcode/Toolchains/Default/usr/bin/clang'),
        (OS.android, 'android-ndk/toolchains/llvm/prebuilt/host/bin/clang'),
        (OS.linux, 'toolchains/llvm/bin/clang'),
      ]) {
        final compiler = compilerAt(path);
        expect(isOhosCompiler(compiler.uri), isFalse);
        final native = _RecordingBuilder();
        final input = buildInput(compiler: compiler.uri, os: os);
        final output = BuildOutputBuilder();
        await buildRustAssets(input, output, nativeBuilder: native);
        expect(native.input, same(input));
        expect(native.output, same(output));
      }
    },
  );

  test('reports missing SDK compiler or sysroot instead of falling back', () {
    final compiler = sdkCompiler(sysroot: false);
    expect(
      () => isOhosCompiler(compiler.uri),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Missing OHOS sysroot'),
        ),
      ),
    );
    compiler.deleteSync();
    expect(
      () => isOhosCompiler(compiler.uri),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Missing OHOS compiler'),
        ),
      ),
    );
  });

  test('derives the existing OHOS Cargo environment from SDK paths', () {
    final compiler = sdkCompiler();
    prepareLinker(compiler);
    final llvm = compiler.parent.parent;
    final libclang = Directory.fromUri(llvm.uri.resolve('lib/'));
    prepareLibclang(libclang);
    final wrapper = File.fromUri(
      compiler.uri.resolve('aarch64-unknown-linux-ohos-clang'),
    );
    final sysroot = Directory.fromUri(llvm.parent.uri.resolve('sysroot/'));
    final flags = '--target=aarch64-linux-ohos --sysroot="${sysroot.path}"';

    expect(ohosBuildEnvironment(compiler.uri, const {}), {
      'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER': wrapper.path,
      'CC_aarch64_unknown_linux_ohos': wrapper.path,
      'AR_aarch64_unknown_linux_ohos': File.fromUri(
        compiler.uri.resolve('llvm-ar'),
      ).path,
      'CFLAGS_aarch64_unknown_linux_ohos': flags,
      'LIBCLANG_PATH': libclang.path,
      'BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_ohos': flags,
    });
  });

  test('uses the allowed LIBCLANG_PATH and rejects invalid directories', () {
    final compiler = sdkCompiler();
    prepareLinker(compiler);
    final libclang = Directory.fromUri(root.uri.resolve('host libclang/'));
    prepareLibclang(libclang);
    expect(
      ohosBuildEnvironment(compiler.uri, {
        'LIBCLANG_PATH': libclang.path,
      })['LIBCLANG_PATH'],
      libclang.path,
    );
    expect(
      () => ohosBuildEnvironment(compiler.uri, const {}),
      throwsStateError,
    );
    Directory.fromUri(
      compiler.parent.parent.uri.resolve('lib/libclang.so/'),
    ).createSync(recursive: true);
    expect(
      () => ohosBuildEnvironment(compiler.uri, const {}),
      throwsStateError,
    );
    expect(
      () => ohosBuildEnvironment(compiler.uri, {'LIBCLANG_PATH': root.path}),
      throwsStateError,
    );
  });

  test('the SDK BuildInput selects OHOS even when targetOS is Linux', () async {
    final compiler = sdkCompiler();
    final native = _RecordingBuilder();
    await expectLater(
      buildRustAssets(
        buildInput(compiler: compiler.uri),
        BuildOutputBuilder(),
        nativeBuilder: native,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('run the OHOS Go/SDK preparation step'),
        ),
      ),
    );
    expect(native.input, isNull);
  });

  test('OHOS rejects unsupported architecture before starting Cargo', () async {
    await expectLater(
      buildRustAssets(
        buildInput(compiler: sdkCompiler().uri, architecture: Architecture.x64),
        BuildOutputBuilder(),
      ),
      throwsStateError,
    );
  });

  test('build_assets=false remains a no-op for native builds', () async {
    final native = _RecordingBuilder();
    final output = BuildOutputBuilder();
    await buildRustAssets(
      buildInput(userDefines: {'build_assets': false}),
      output,
      nativeBuilder: native,
    );
    expect(native.input, isNull);
    expect(BuildOutput(output.json).dependencies, isEmpty);
  });
}

class _RecordingBuilder implements Builder {
  BuildInput? input;
  BuildOutputBuilder? output;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    Object? logger,
  }) async {
    this.input = input;
    this.output = output;
  }
}

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, buildRustAssets);
}

Future<void> buildRustAssets(
  BuildInput input,
  BuildOutputBuilder output, {
  Builder? nativeBuilder,
}) async {
  if (input.userDefines['build_assets'] == false) {
    stdout.writeln('Skipping the Rust build: user-define build_assets=false');
    return;
  }
  if (input.config.buildCodeAssets &&
      isOhosCompiler(input.config.code.cCompiler?.compiler)) {
    if (input.config.code.targetArchitecture != Architecture.arm64) {
      throw StateError('The OHOS app currently packages arm64 only');
    }
    await _buildOhos(input, output);
    return;
  }
  await (nativeBuilder ??
          FlutterRustBridgeNativeAssetsBuilder(
            cratePath: 'rust',
            extraCargoEnvironmentVariables: _bindgenEnvironment(input),
          ))
      .run(input: input, output: output, logger: null);
}

bool isOhosCompiler(Uri? compiler) {
  if (compiler == null ||
      compiler.scheme != 'file' ||
      !RegExp(r'/native/llvm/bin/clang(?:\.exe)?$').hasMatch(compiler.path)) {
    return false;
  }
  final executable = File.fromUri(compiler);
  if (!executable.existsSync()) {
    throw StateError('Missing OHOS compiler: ${executable.path}');
  }
  final sysroot = Directory.fromUri(
    executable.parent.parent.parent.uri.resolve('sysroot/'),
  );
  if (!sysroot.existsSync()) {
    throw StateError('Missing OHOS sysroot: ${sysroot.path}');
  }
  return true;
}

void checkOhosElf(String metadata) {
  if (!RegExp(r'Machine:\s+AArch64\b').hasMatch(metadata) ||
      RegExp(
        r'\[(?:libc\.so\.6|ld-linux-aarch64\.so\.1|libstdc\+\+\.so\.6|libpthread\.so\.0|libdl\.so\.2|libm\.so\.6|librt\.so\.1)\]',
      ).hasMatch(metadata)) {
    throw StateError(
      'Incompatible OHOS ELF architecture or GNU Linux dependency',
    );
  }
}

Map<String, String> ohosBuildEnvironment(
  Uri compiler,
  Map<String, String> environment,
) {
  if (!isOhosCompiler(compiler)) {
    throw StateError('Not an OHOS SDK compiler: $compiler');
  }
  final llvm = File.fromUri(compiler).parent.parent;
  final linker = File.fromUri(
    llvm.uri.resolve('bin/aarch64-unknown-linux-ohos-clang'),
  );
  if (!linker.existsSync()) {
    throw StateError(
      'Missing OHOS linker wrapper: ${linker.path}; run the OHOS Go/SDK '
      'preparation step (.github/setup-ohos-go.sh) first',
    );
  }
  final libclang = Directory(
    environment['LIBCLANG_PATH'] ??
        Directory.fromUri(llvm.uri.resolve('lib/')).path,
  );
  if (!libclang.existsSync() ||
      !libclang.listSync().whereType<File>().any(_isLibclang)) {
    throw StateError('No libclang in ${libclang.path}; set LIBCLANG_PATH');
  }
  final sysroot = Directory.fromUri(llvm.parent.uri.resolve('sysroot/'));
  final clangArgs = '--target=aarch64-linux-ohos --sysroot="${sysroot.path}"';
  return {
    'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER': linker.path,
    'CC_aarch64_unknown_linux_ohos': linker.path,
    'AR_aarch64_unknown_linux_ohos': File.fromUri(
      compiler.resolve(
        'llvm-ar${compiler.path.endsWith('.exe') ? '.exe' : ''}',
      ),
    ).path,
    'CFLAGS_aarch64_unknown_linux_ohos': clangArgs,
    'LIBCLANG_PATH': libclang.path,
    'BINDGEN_EXTRA_CLANG_ARGS_aarch64_unknown_linux_ohos': clangArgs,
  };
}

Future<void> _buildOhos(BuildInput input, BuildOutputBuilder output) async {
  const target = 'aarch64-unknown-linux-ohos';
  final compiler = input.config.code.cCompiler!.compiler;
  final environment = ohosBuildEnvironment(compiler, Platform.environment);
  final llvm = File.fromUri(compiler).parent.parent;
  final crate = Directory.fromUri(input.packageRoot.resolve('rust/'));
  final targetDirectory = Directory.fromUri(
    input.outputDirectory.resolve('ohos-target/'),
  );
  final result = await Process.run(
    'cargo',
    [
      'build',
      '--locked',
      '--release',
      '--target',
      target,
      '--target-dir',
      targetDirectory.path,
    ],
    workingDirectory: crate.path,
    environment: environment,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw StateError('OHOS Rust build failed (${result.exitCode})');
  }
  final library = File(
    '${targetDirectory.path}/$target/release/librust_api.so',
  );
  if (!library.existsSync() || library.lengthSync() == 0) {
    throw StateError('Missing OHOS Rust code asset: ${library.path}');
  }
  final metadata = await Process.run(
    File.fromUri(
      llvm.uri.resolve(
        'bin/llvm-readelf${compiler.path.endsWith('.exe') ? '.exe' : ''}',
      ),
    ).path,
    ['-h', '-d', library.path],
  );
  if (metadata.exitCode != 0) {
    throw StateError('Cannot inspect OHOS Rust library: ${metadata.stderr}');
  }
  checkOhosElf(metadata.stdout as String);
  stdout.write(metadata.stdout);
  output.dependencies.addAll([
    crate.uri.resolve('Cargo.toml'),
    crate.uri.resolve('Cargo.lock'),
    crate.uri.resolve('rust-toolchain.toml'),
    ...Directory.fromUri(
      crate.uri.resolve('src/'),
    ).listSync(recursive: true).whereType<File>().map((file) => file.uri),
  ]);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/rust/frb_generated.io.dart',
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
}

// rquickjs runs bindgen on Android, which must load the NDK's libclang; Linux
// NDKs before r26 keep it under lib64, later ones and every macOS NDK under lib.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path};
    }
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64); the NDK Flutter '
    'passed cannot run bindgen for rquickjs',
  );
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}

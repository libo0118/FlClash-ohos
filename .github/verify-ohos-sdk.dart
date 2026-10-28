import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/native_assets/ohos/native_assets.dart';
import 'package:process/process.dart';

// Use the pinned Flutter tool's locator and native-assets resolver, not NDK env alone.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected the HarmonyOS SDK root and OHOS NDK root.');
  }
  await runInContext(() async {
    final sdk = globals.harmonySdk;
    if (sdk == null || !sdk.isValidDirectory) {
      throw StateError('Flutter could not locate a valid HarmonyOS SDK.');
    }
    if (!globals.fs.path.equals(sdk.sdkPath, args[0])) {
      throw StateError('Flutter selected ${sdk.sdkPath}, expected ${args[0]}.');
    }
    if (sdk.apiAvailable.isEmpty || sdk.hdcPath == null) {
      throw StateError('Flutter could not resolve the SDK API version or hdc.');
    }
    final compiler = await cCompilerConfigOhos();
    if (compiler == null) {
      throw StateError(
        'Flutter could not resolve the OHOS native-assets toolchain.',
      );
    }
    final suffix = globals.platform.isWindows ? '.exe' : '';
    final tools = {
      'clang': compiler.compiler,
      'llvm-ar': compiler.archiver,
      'ld.lld': compiler.linker,
    };
    for (final tool in tools.entries) {
      final expected = globals.fs.path.join(
        args[1],
        'native',
        'llvm',
        'bin',
        '${tool.key}$suffix',
      );
      if (!globals.fs.path.equals(tool.value.toFilePath(), expected)) {
        throw StateError('Flutter selected ${tool.value}, expected $expected.');
      }
      print('${tool.key}: ${tool.value}');
    }
    print('${sdk.name}: ${sdk.sdkPath} (${sdk.apiAvailable.join(', ')})');
    print('hdc: ${sdk.hdcPath}');
  }, overrides: {ProcessManager: () => const LocalProcessManager()});
}

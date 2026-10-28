import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/picker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

class _SaveFilePicker extends FilePickerPlatform {
  String? result;
  Exception? error;
  Uint8List? savedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    required String fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    required Uint8List bytes,
    Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) async {
    if (error case final error?) {
      throw error;
    }
    savedBytes = bytes;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformFileExt.readBytes', () {
    test('loads bytes from the picked file path', () async {
      final directory = await Directory.systemTemp.createTemp(
        'fl_clash_picker_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = File('${directory.path}/profile.yaml');
      await file.writeAsString('mixed-port: 7890');

      final platformFile = PlatformFile(
        name: 'profile.yaml',
        size: await file.length(),
        path: file.path,
      );

      final bytes = await platformFile.readBytes();

      expect(String.fromCharCodes(bytes), 'mixed-port: 7890');
    });
  });

  group('Picker.saveFile', () {
    late Directory directory;
    late _SaveFilePicker platformPicker;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('fl_clash_save_test_');
      await useAppPaths(directory);
      final previous = FilePickerPlatform.instance;
      platformPicker = _SaveFilePicker();
      FilePickerPlatform.instance = platformPicker;
      addTearDown(() async {
        FilePickerPlatform.instance = previous;
        await directory.delete(recursive: true);
      });
    });

    for (final (path, expected) in [
      (
        'content://documents/tree/profile%3A1',
        Uri.parse('content://documents/tree/profile%3A1'),
      ),
      (
        'file:///tmp/profile%20one.yaml',
        Uri.parse('file:///tmp/profile%20one.yaml'),
      ),
      (
        '/tmp/profile #%.yaml',
        Uri.file('/tmp/profile #%.yaml', windows: false),
      ),
      (
        r'C:\Users\test\profile #%.yaml',
        Uri.file(r'C:\Users\test\profile #%.yaml', windows: true),
      ),
      (
        'C:/Users/test/profile #%.yaml',
        Uri.file('C:/Users/test/profile #%.yaml', windows: true),
      ),
      (
        r'\\server\share\profile.yaml',
        Uri.file(r'\\server\share\profile.yaml', windows: true),
      ),
    ]) {
      test('preserves the selected location $path and passes bytes', () async {
        platformPicker.result = path;
        final bytes = Uint8List.fromList([0, 1, 255]);

        expect(await Picker().saveFile('profile.yaml', bytes), expected);
        expect(platformPicker.savedBytes, bytes);
      });
    }

    test('returns null when the picker is cancelled', () async {
      expect(await Picker().saveFile('profile.yaml', Uint8List(0)), isNull);
    });

    for (final cancelled in [false, true]) {
      test(
        'cleans up the source after ${cancelled ? 'cancellation' : 'saving'}',
        () async {
          final file = File('${directory.path}/backup.zip');
          await file.writeAsBytes([1, 2, 3]);
          platformPicker.result = cancelled
              ? null
              : 'content://documents/backup';

          expect(
            await Picker().saveFileWithPath('backup.zip', file.path),
            cancelled ? isNull : Uri.parse('content://documents/backup'),
          );
          expect(platformPicker.savedBytes, [1, 2, 3]);
          expect(await file.exists(), false);
        },
      );
    }

    test('preserves the source and propagates picker errors', () async {
      final file = File('${directory.path}/backup.zip');
      await file.writeAsBytes([1, 2, 3]);
      final error = platformPicker.error = const FileSystemException(
        'save failed',
      );

      await expectLater(
        Picker().saveFileWithPath('backup.zip', file.path),
        throwsA(same(error)),
      );
      expect(await file.readAsBytes(), [1, 2, 3]);
    });

    test('saves an empty file when the temporary source is missing', () async {
      final path = '${directory.path}/missing/backup.zip';
      platformPicker.result = 'content://documents/backup';

      await Picker().saveFileWithPath('backup.zip', path);

      expect(platformPicker.savedBytes, isEmpty);
      expect(await File(path).exists(), false);
    });
  });
}

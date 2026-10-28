import 'dart:io';

import 'package:test/test.dart';

import 'source_paths.dart';

void main() {
  test('source paths use repository-relative forward slashes', () {
    for (final path in [
      'lib/l10n/l10n.dart',
      r'lib\l10n\l10n.dart',
      File('lib/l10n/l10n.dart').absolute.path,
    ]) {
      expect(File(path).sourcePath, 'lib/l10n/l10n.dart');
    }
  });
}

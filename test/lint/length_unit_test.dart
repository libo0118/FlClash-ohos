import 'dart:io';

import 'package:test/test.dart';

import 'source_paths.dart';

final _pxLength = RegExp(r'\b\d+(?:\.\d+)?\s?px\b', caseSensitive: false);

void main() {
  test('lib and test give Flutter lengths in dp, not px', () {
    final offenders = <String>[];

    for (final root in ['lib', 'test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File ||
            !entity.sourcePath.endsWith('.dart') ||
            entity.sourcePath.endsWith('.g.dart') ||
            entity.sourcePath.contains('/generated/')) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          final match = _pxLength.firstMatch(lines[index]);
          if (match != null) {
            offenders.add(
              '${entity.sourcePath}:${index + 1} — "${match[0]}"; write Flutter '
              'lengths in dp and spell out a physical pixel.',
            );
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;

extension SourcePath on FileSystemEntity {
  String get sourcePath => p.relative(path).replaceAll(r'\', '/');
}

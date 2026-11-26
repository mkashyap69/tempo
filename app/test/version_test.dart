import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/core/version.dart';

/// The version You shows is the one the build carries.
void main() {
  test('version.dart matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $appVersion+$appBuild');
  });
}

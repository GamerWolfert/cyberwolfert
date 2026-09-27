import 'dart:async';

/// Filesysteem-helpers alleen op native platforms (stub op Web).
Future<void> ensureDir(String path) async {}
Future<String> writeStream(String path, Stream<List<int>> stream,
    {int total = 0, void Function(double progress)? onProgress}) async => '';
Future<int> fileLength(String path) async => 0;
Future<void> deleteFile(String path) async {}
Future<void> copyFile(String from, String to) async {
  throw UnsupportedError('alleen in de app, niet op Web');
}

Future<bool> fileExists(String path) async => false;

import 'dart:async';
import 'dart:io';

Future<void> ensureDir(String path) async {
  await Directory(path).create(recursive: true);
}

Future<String> writeStream(String path, Stream<List<int>> stream,
    {int total = 0, void Function(double progress)? onProgress}) async {
  final file = File(path);
  final sink = file.openWrite();
  var done = 0;
  await for (final chunk in stream) {
    sink.add(chunk);
    done += chunk.length;
    if (total > 0) onProgress?.call(done / total);
  }
  await sink.close();
  return file.path;
}

Future<int> fileLength(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return 0;
  }
}

Future<void> deleteFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}

Future<bool> fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

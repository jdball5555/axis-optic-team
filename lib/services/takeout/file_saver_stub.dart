import 'dart:io';

Future<void> saveFile({required String filename, required String content}) async {
  try {
    final dir = Directory('/sdcard/Download');
    if (await dir.exists()) {
      final file = File('/sdcard/Download/$filename');
      await file.writeAsString(content);
      return;
    }
  } catch (_) {}
}

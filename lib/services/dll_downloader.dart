import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DllDownloader {
  static const String dllName = 'audio_engine.dll';

  static const String dllUrl = 'https://raw.githubusercontent.com/alireza-turk-oglan/soundrecorder/refs/heads/main/native/audio_engine/audio_engine.dll';

  static Future<void> ensureDllExists() async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      final executablePath = Platform.resolvedExecutable;
      final executableDirectory = File(executablePath).parent.path;

      final dllFile = File('$executableDirectory${Platform.pathSeparator}$dllName');

      if (await dllFile.exists()) {
        debugPrint('DLL already exists : ${dllFile.path}');
        return;
      }

      debugPrint('Downloading DLL...');

      final response = await http.get(Uri.parse(dllUrl));

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download DLL. '
          'Status code : ${response.statusCode}',
        );
      }

      await dllFile.writeAsBytes(response.bodyBytes, flush: true);

      debugPrint('DLL downloaded to : ${dllFile.path}');
    } catch (e) {
      debugPrint('DLL download error : $e');
    }
  }
}

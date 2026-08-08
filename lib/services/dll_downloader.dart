import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum DllDownloadStatus { checking, downloading, completed, alreadyExists, error }

class DllDownloader {
  static const String dllName = 'audio_engine.dll';

  static const String dllUrl = 'https://raw.githubusercontent.com/alireza-turk-oglan/soundrecorder/refs/heads/main/native/audio_engine/audio_engine.dll';

  static Future<void> ensureDllExists({void Function(DllDownloadStatus status, String message)? onStatus, bool autoRestart = true}) async {
    if (!Platform.isWindows) {
      return;
    }

    onStatus?.call(DllDownloadStatus.checking, 'در حال بررسی فایل...');

    try {
      final executablePath = Platform.resolvedExecutable;
      final executableDirectory = File(executablePath).parent.path;

      final dllFile = File('$executableDirectory${Platform.pathSeparator}$dllName');

      if (await dllFile.exists()) {
        debugPrint('DLL already exists : ${dllFile.path}');
        onStatus?.call(DllDownloadStatus.alreadyExists, 'فایل مورد نیاز از قبل موجود است.');
        return;
      }

      debugPrint('Downloading DLL...');
      onStatus?.call(DllDownloadStatus.downloading, 'در حال دانلود فایل مورد نیاز، لطفاً صبر کنید...');

      final response = await http.get(Uri.parse(dllUrl));

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download DLL. '
          'Status code : ${response.statusCode}',
        );
      }

      await dllFile.writeAsBytes(response.bodyBytes, flush: true);

      debugPrint('DLL downloaded to : ${dllFile.path}');
      onStatus?.call(DllDownloadStatus.completed, 'دانلود کامل شد. برنامه در حال راه‌اندازی مجدد است...');

      if (autoRestart) {
        await Future.delayed(const Duration(seconds: 1));
        _restartApp();
      }
    } catch (e) {
      debugPrint('DLL download error : $e');
      onStatus?.call(DllDownloadStatus.error, 'خطا در دانلود فایل: $e');
    }
  }

  static void _restartApp() {
    try {
      final executablePath = Platform.resolvedExecutable;
      final arguments = Platform.executableArguments;

      Process.start(executablePath, arguments, mode: ProcessStartMode.detached).then((_) {
        exit(0);
      });
    } catch (e) {
      debugPrint('Restart error : $e');
    }
  }
}

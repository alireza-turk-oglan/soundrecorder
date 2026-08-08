import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AudioFormat { wav, mp3, aacM4a, flac, ogg }

extension AudioFormatX on AudioFormat {
  String get extension {
    switch (this) {
      case AudioFormat.wav:
        return 'wav';
      case AudioFormat.mp3:
        return 'mp3';
      case AudioFormat.aacM4a:
        return 'm4a';
      case AudioFormat.flac:
        return 'flac';
      case AudioFormat.ogg:
        return 'ogg';
    }
  }

  String get label {
    switch (this) {
      case AudioFormat.wav:
        return 'WAV (بدون افت کیفیت)';
      case AudioFormat.mp3:
        return 'MP3';
      case AudioFormat.aacM4a:
        return 'AAC / M4A';
      case AudioFormat.flac:
        return 'FLAC (بدون افت کیفیت ، فشرده)';
      case AudioFormat.ogg:
        return 'OGG Vorbis';
    }
  }
}

class ExportService {
  static Future<String> _ensureFfmpeg() async {
    final supportDir = await getApplicationSupportDirectory();
    final ffmpegPath = p.join(supportDir.path, 'ffmpeg.exe');
    final file = File(ffmpegPath);
    if (!await file.exists()) {
      final bytes = await File(p.join('assets', 'ffmpeg', 'ffmpeg.exe')).readAsBytes();
      await file.writeAsBytes(bytes);
    }
    return ffmpegPath;
  }

  static Future<String> convert({required String sourceWavPath, required String destPath, required AudioFormat format, int bitrateKbps = 320}) async {
    if (format == AudioFormat.wav) {
      await File(sourceWavPath).copy(destPath);
      return destPath;
    }

    final ffmpeg = await _ensureFfmpeg();
    final args = <String>['-y', '-i', sourceWavPath];

    switch (format) {
      case AudioFormat.mp3:
        args.addAll(['-codec:a', 'libmp3lame', '-b:a', '${bitrateKbps}k']);
        break;
      case AudioFormat.aacM4a:
        args.addAll(['-codec:a', 'aac', '-b:a', '${bitrateKbps}k']);
        break;
      case AudioFormat.flac:
        args.addAll(['-codec:a', 'flac']);
        break;
      case AudioFormat.ogg:
        args.addAll(['-codec:a', 'libvorbis', '-b:a', '${bitrateKbps}k']);
        break;
      case AudioFormat.wav:
        break;
    }
    args.add(destPath);

    final result = await Process.run(ffmpeg, args);
    if (result.exitCode != 0) {
      throw Exception('Error in format conversion : ${result.stderr}');
    }
    return destPath;
  }
}

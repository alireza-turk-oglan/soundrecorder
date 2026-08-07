// recorder_controller.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'audio_engine_ffi.dart';
import 'export_service.dart';

enum RecState { idle, recording, paused }

class RecorderController extends ChangeNotifier {
  final _engine = AudioEngine.instance;

  RecState state = RecState.idle;
  Duration elapsed = Duration.zero;
  double micLevel = 0.0;
  double sysLevel = 0.0;

  double micVolume = 1.0;
  double sysVolume = 1.0;
  bool micMuted = false;
  bool sysMuted = false;

  String? outputDir;

  String? _currentWavPath;
  Timer? _pollTimer;

  bool _initialized = false;

  Future<String> resolveOutputDir() async {
    if (outputDir != null && outputDir!.isNotEmpty) return outputDir!;
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'WindowsAudioRecorder');
  }

  Future<String> _resolveTempRecordingDir() async {
    final tempBase = await getTemporaryDirectory();
    return p.join(tempBase.path, 'WinAudioRecorderTemp');
  }

  Future<void> pickOutputDirectory() async {
    final selected = await FilePicker.getDirectoryPath();
    if (selected != null && selected.isNotEmpty) {
      outputDir = selected;
      notifyListeners();
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = _engine.init();
    if (!_initialized) {
      throw Exception('راه‌اندازی موتور صدا ناموفق بود.');
    }
  }

  Future<void> start() async {
    try {
      await init();
    } catch (e) {
      throw Exception('An error occurred while starting the audio engine. : $e');
    }

    late final Directory recDir;
    try {
      final basePath = await _resolveTempRecordingDir();
      recDir = Directory(basePath);
      if (!await recDir.exists()) {
        await recDir.create(recursive: true);
      }
    } on FileSystemException catch (e) {
      throw Exception('ساخت پوشه موقت ضبط ممکن نشد (${e.message}). دسترسی نوشتن در پوشه Temp سیستم را بررسی کنید.');
    } catch (e) {
      throw Exception('ساخت پوشه موقت ضبط با خطا مواجه شد: $e');
    }

    final now = Jalali.now();

    final dateshamsi =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}_${now.minute.toString().padLeft(2, '0')}';
    final wavPath = p.join(recDir.path, 'recording_$dateshamsi.wav');

    try {
      _engine.setMicVolume(micVolume);
      _engine.setSystemVolume(sysVolume);
      _engine.setMicMuted(micMuted);
      _engine.setSystemMuted(sysMuted);

      final ok = _engine.startRecording(wavPath);
      if (!ok) {
        throw Exception('شروع ضبط ناموفق بود. دسترسی میکروفن یا خروجی صدا یا دسترسی ذخیره فایل را بررسی کنید.');
      }
    } catch (e) {
      _currentWavPath = null;
      rethrow;
    }

    _currentWavPath = wavPath;
    state = RecState.recording;
    _startPolling();
    notifyListeners();
  }

  void pause() {
    _engine.pause();
    state = RecState.paused;
    notifyListeners();
  }

  void resume() {
    _engine.resume();
    state = RecState.recording;
    notifyListeners();
  }

  Future<String?> stop() async {
    _engine.stopRecording();
    _stopPolling();
    state = RecState.idle;
    elapsed = Duration.zero;
    notifyListeners();
    return _currentWavPath;
  }

  void setMicVolume(double v) {
    micVolume = v;
    _engine.setMicVolume(v);
    notifyListeners();
  }

  void setSysVolume(double v) {
    sysVolume = v;
    _engine.setSystemVolume(v);
    notifyListeners();
  }

  void toggleMicMuted() {
    micMuted = !micMuted;
    _engine.setMicMuted(micMuted);
    notifyListeners();
  }

  void toggleSysMuted() {
    sysMuted = !sysMuted;
    _engine.setSystemMuted(sysMuted);
    notifyListeners();
  }

  Future<String?> saveRecordingAs(AudioFormat format, {int bitrateKbps = 320}) async {
    if (_currentWavPath == null) throw Exception('فایلی برای ذخیره وجود ندارد');
    final tempWavPath = _currentWavPath!;

    final now = Jalali.now();
    final suggestedName = 'recording_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.${format.extension}';

    final initialDir = (outputDir != null && outputDir!.isNotEmpty) ? outputDir : null;

    final savePath = await FilePicker.saveFile(
      dialogTitle: 'محل ذخیره فایل ضبط‌شده را انتخاب کنید',
      fileName: suggestedName,
      initialDirectory: initialDir,
      type: FileType.custom,
      allowedExtensions: [format.extension],
    );

    if (savePath == null || savePath.isEmpty) {
      return null;
    }

    var finalPath = savePath;
    if (p.extension(finalPath).toLowerCase() != '.${format.extension}') {
      finalPath = '$finalPath.${format.extension}';
    }

    String resultPath;
    if (format == AudioFormat.wav) {
      await File(tempWavPath).copy(finalPath);
      resultPath = finalPath;
    } else {
      resultPath = await ExportService.convert(sourceWavPath: tempWavPath, destPath: finalPath, format: format, bitrateKbps: bitrateKbps);
    }

    try {
      final tempFile = File(tempWavPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}

    outputDir = p.dirname(resultPath);
    _currentWavPath = null;
    notifyListeners();
    return resultPath;
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed = _engine.getElapsed();
      final levels = _engine.getLevels();
      micLevel = levels.$1;
      sysLevel = levels.$2;
      notifyListeners();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    micLevel = 0.0;
    sysLevel = 0.0;
  }

  @override
  void dispose() {
    _stopPolling();
    _engine.shutdown();
    super.dispose();
  }
}

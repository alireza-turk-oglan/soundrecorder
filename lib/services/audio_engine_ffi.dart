import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef _AeInitializeNative = Int32 Function();
typedef _AeInitializeDart = int Function();

typedef _AeShutdownNative = Void Function();
typedef _AeShutdownDart = void Function();

typedef _AeStartRecordingNative =
    Int32 Function(Pointer<Utf16> path, Int32 sampleRate);
typedef _AeStartRecordingDart =
    int Function(Pointer<Utf16> path, int sampleRate);

typedef _AeStopRecordingNative = Int32 Function();
typedef _AeStopRecordingDart = int Function();

typedef _AeVoidNative = Void Function();
typedef _AeVoidDart = void Function();

typedef _AeGetStateNative = Int32 Function();
typedef _AeGetStateDart = int Function();

typedef _AeSetFloatNative = Void Function(Float v);
typedef _AeSetFloatDart = void Function(double v);

typedef _AeSetIntNative = Void Function(Int32 v);
typedef _AeSetIntDart = void Function(int v);

typedef _AeGetLevelsNative =
    Void Function(Pointer<Float> mic, Pointer<Float> sys);
typedef _AeGetLevelsDart =
    void Function(Pointer<Float> mic, Pointer<Float> sys);

typedef _AeGetElapsedMsNative = Int64 Function();
typedef _AeGetElapsedMsDart = int Function();

class AudioEngine {
  AudioEngine._internal() {
    _lib = DynamicLibrary.open('audio_engine.dll');

    _initialize = _lib.lookupFunction<_AeInitializeNative, _AeInitializeDart>(
      'AE_Initialize',
    );
    _shutdown = _lib.lookupFunction<_AeShutdownNative, _AeShutdownDart>(
      'AE_Shutdown',
    );
    _startRecording = _lib
        .lookupFunction<_AeStartRecordingNative, _AeStartRecordingDart>(
          'AE_StartRecording',
        );
    _stopRecording = _lib
        .lookupFunction<_AeStopRecordingNative, _AeStopRecordingDart>(
          'AE_StopRecording',
        );
    _pause = _lib.lookupFunction<_AeVoidNative, _AeVoidDart>('AE_Pause');
    _resume = _lib.lookupFunction<_AeVoidNative, _AeVoidDart>('AE_Resume');
    _getState = _lib.lookupFunction<_AeGetStateNative, _AeGetStateDart>(
      'AE_GetState',
    );
    _setMicVolume = _lib.lookupFunction<_AeSetFloatNative, _AeSetFloatDart>(
      'AE_SetMicVolume',
    );
    _setSystemVolume = _lib.lookupFunction<_AeSetFloatNative, _AeSetFloatDart>(
      'AE_SetSystemVolume',
    );
    _setMicMuted = _lib.lookupFunction<_AeSetIntNative, _AeSetIntDart>(
      'AE_SetMicMuted',
    );
    _setSystemMuted = _lib.lookupFunction<_AeSetIntNative, _AeSetIntDart>(
      'AE_SetSystemMuted',
    );
    _getLevels = _lib.lookupFunction<_AeGetLevelsNative, _AeGetLevelsDart>(
      'AE_GetLevels',
    );
    _getElapsedMs = _lib
        .lookupFunction<_AeGetElapsedMsNative, _AeGetElapsedMsDart>(
          'AE_GetElapsedMs',
        );
  }

  static final AudioEngine instance = AudioEngine._internal();

  late final DynamicLibrary _lib;
  late final _AeInitializeDart _initialize;
  late final _AeShutdownDart _shutdown;
  late final _AeStartRecordingDart _startRecording;
  late final _AeStopRecordingDart _stopRecording;
  late final _AeVoidDart _pause;
  late final _AeVoidDart _resume;
  late final _AeGetStateDart _getState;
  late final _AeSetFloatDart _setMicVolume;
  late final _AeSetFloatDart _setSystemVolume;
  late final _AeSetIntDart _setMicMuted;
  late final _AeSetIntDart _setSystemMuted;
  late final _AeGetLevelsDart _getLevels;
  late final _AeGetElapsedMsDart _getElapsedMs;

  bool init() => _initialize() == 0;
  void shutdown() => _shutdown();

  bool startRecording(String wavPath, {int sampleRate = 48000}) {
    final ptr = wavPath.toNativeUtf16();
    try {
      return _startRecording(ptr, sampleRate) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  bool stopRecording() => _stopRecording() == 0;
  void pause() => _pause();
  void resume() => _resume();

  /// 0 = stopped, 1 = recording, 2 = paused
  int getState() => _getState();

  void setMicVolume(double v) => _setMicVolume(v);
  void setSystemVolume(double v) => _setSystemVolume(v);
  void setMicMuted(bool m) => _setMicMuted(m ? 1 : 0);
  void setSystemMuted(bool m) => _setSystemMuted(m ? 1 : 0);

  (double mic, double sys) getLevels() {
    final micPtr = calloc<Float>();
    final sysPtr = calloc<Float>();
    try {
      _getLevels(micPtr, sysPtr);
      return (micPtr.value, sysPtr.value);
    } finally {
      calloc.free(micPtr);
      calloc.free(sysPtr);
    }
  }

  Duration getElapsed() => Duration(milliseconds: _getElapsedMs());
}

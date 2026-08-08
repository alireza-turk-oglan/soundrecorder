#pragma once

#ifdef AUDIOENGINE_EXPORTS
#define AE_API extern "C" __declspec(dllexport)
#else
#define AE_API extern "C" __declspec(dllimport)
#endif

#define AE_OK 0
#define AE_ERR_INIT -1
#define AE_ERR_DEVICE -2
#define AE_ERR_ALREADY_RUNNING -3
#define AE_ERR_FILE -4
#define AE_ERR_NOT_RUNNING -5
#define AE_ERR_INVALID_ARGUMENT -6
#define AE_ERR_UNSUPPORTED -7

AE_API int AE_Initialize();

AE_API void AE_Shutdown();

AE_API int AE_StartRecording(const wchar_t* outputWavPathUtf16, int sampleRate);

AE_API int AE_StopRecording();

AE_API void AE_Pause();
AE_API void AE_Resume();

AE_API int AE_GetState();

AE_API void AE_SetMicVolume(float volume);
AE_API void AE_SetSystemVolume(float volume);

AE_API void AE_SetMicMuted(int muted);
AE_API void AE_SetSystemMuted(int muted);

AE_API void AE_GetLevels(float* micLevel, float* systemLevel);

AE_API long long AE_GetElapsedMs();

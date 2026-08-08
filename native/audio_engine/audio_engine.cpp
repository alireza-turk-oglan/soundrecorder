#define AUDIOENGINE_EXPORTS
#define NOMINMAX
#include "audio_engine.h"

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <avrt.h>

#include <atomic>
#include <thread>
#include <mutex>
#include <deque>
#include <vector>
#include <cstdio>
#include <cmath>
#include <algorithm>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "avrt.lib")

// ---------- تنظیمات ثابت خروجی ----------
static const int kOutChannels = 2;
static const int kOutSampleRate = 48000;
static const size_t kMaxMixerFramesPerPass = 4800; // 100 ms at 48 kHz

struct SampleQueue {
    std::mutex mtx;
    std::deque<float> data;
};

struct EngineState {
    std::atomic<bool> initialized{false};
    bool comInitialized = false;
    std::atomic<int> recState{0}; // 0 stopped, 1 recording, 2 paused

    IMMDeviceEnumerator* enumerator = nullptr;

    // منبع سیستم (loopback از دستگاه پخش پیش‌فرض)
    IMMDevice* renderDevice = nullptr;
    IAudioClient* renderClient = nullptr;
    IAudioCaptureClient* renderCapture = nullptr;
    WAVEFORMATEX* renderFormat = nullptr;
    HANDLE renderStopEvent = nullptr;
    std::thread renderThread;

    // منبع میکروفن (دستگاه ضبط پیش‌فرض)
    IMMDevice* micDevice = nullptr;
    IAudioClient* micClient = nullptr;
    IAudioCaptureClient* micCapture = nullptr;
    WAVEFORMATEX* micFormat = nullptr;
    HANDLE micStopEvent = nullptr;
    std::thread micThread;

    SampleQueue sysQueue;
    SampleQueue micQueue;

    // میکسر
    std::thread mixerThread;
    std::atomic<bool> mixerRunning{false};

    // پارامترهای کنترل کاربر
    std::atomic<float> micVolume{1.0f};
    std::atomic<float> sysVolume{1.0f};
    std::atomic<bool> micMuted{false};
    std::atomic<bool> sysMuted{false};

    // متر سطح صدا برای UI
    std::atomic<float> micLevel{0.0f};
    std::atomic<float> sysLevel{0.0f};

    // فایل خروجی
    FILE* wavFile = nullptr;
    std::mutex wavMutex;
    uint64_t writtenFrames = 0;
    LARGE_INTEGER startTime{};
    LARGE_INTEGER pausedAccum{};
    LARGE_INTEGER pauseStartTime{};
    LARGE_INTEGER qpcFreq{};
};

static EngineState g_state;

static void WriteWavHeaderPlaceholder(FILE* f) {
    struct WavHeader {
        char riff[4] = {'R','I','F','F'};
        uint32_t chunkSize = 0;
        char wave[4] = {'W','A','V','E'};
        char fmt[4] = {'f','m','t',' '};
        uint32_t fmtSize = 16;
        uint16_t audioFormat = 3;
        uint16_t numChannels = (uint16_t)kOutChannels;
        uint32_t sampleRate = (uint32_t)kOutSampleRate;
        uint32_t byteRate = (uint32_t)kOutSampleRate * kOutChannels * 4;
        uint16_t blockAlign = (uint16_t)(kOutChannels * 4);
        uint16_t bitsPerSample = 32;
        char data[4] = {'d','a','t','a'};
        uint32_t dataSize = 0;
    } header;
    fwrite(&header, sizeof(header), 1, f);
}

static void PatchWavHeaderAndClose(FILE* f, uint64_t totalFrames) {
    uint32_t dataBytes = (uint32_t)(totalFrames * kOutChannels * sizeof(float));
    uint32_t riffSize = 36 + dataBytes;
    fseek(f, 4, SEEK_SET);
    fwrite(&riffSize, sizeof(riffSize), 1, f);
    fseek(f, 40, SEEK_SET);
    fwrite(&dataBytes, sizeof(dataBytes), 1, f);
    fflush(f);
    fclose(f);
}

static bool IsFloatFormat(const WAVEFORMATEX* fmt) {
    if (!fmt) return false;
    if (fmt->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (fmt->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
        fmt->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
        const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(fmt);
        return IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
    }
    return false;
}

static void ReadStereoFrame(const BYTE* frame, const WAVEFORMATEX* fmt,
                            float& left, float& right) {
    left = right = 0.0f;
    if (!frame || !fmt || fmt->nChannels == 0) return;

    const int bytesPerSample = fmt->wBitsPerSample / 8;
    const bool isFloat = IsFloatFormat(fmt);

    if (isFloat && bytesPerSample == 4) {
        const float* s = reinterpret_cast<const float*>(frame);
        left = s[0];
        right = (fmt->nChannels > 1) ? s[1] : s[0];
    } else if (!isFloat && bytesPerSample == 2) {
        const int16_t* s = reinterpret_cast<const int16_t*>(frame);
        left = s[0] / 32768.0f;
        right = (fmt->nChannels > 1) ? s[1] / 32768.0f : left;
    } else if (!isFloat && bytesPerSample == 4) {
        const int32_t* s = reinterpret_cast<const int32_t*>(frame);
        left = s[0] / 2147483648.0f;
        right = (fmt->nChannels > 1) ? s[1] / 2147483648.0f : left;
    }
}

static float CalculatePeak(const BYTE* data, UINT32 frames, const WAVEFORMATEX* fmt) {
    if (!data || !fmt || frames == 0) return 0.0f;

    float peak = 0.0f;
    for (UINT32 i = 0; i < frames; ++i) {
        float l = 0.0f, r = 0.0f;
        ReadStereoFrame(data + static_cast<size_t>(i) * fmt->nBlockAlign, fmt, l, r);
        peak = std::max(peak, std::fabs(l));
        peak = std::max(peak, std::fabs(r));
    }
    return std::clamp(peak, 0.0f, 1.0f);
}

static void PushResampled(SampleQueue& q, const BYTE* data, UINT32 frames,
                           const WAVEFORMATEX* fmt) {
    if (frames == 0 || !data || !fmt || fmt->nChannels == 0 || fmt->nSamplesPerSec == 0) return;

    std::vector<float> srcStereo;
    srcStereo.reserve(static_cast<size_t>(frames) * 2);

    for (UINT32 i = 0; i < frames; ++i) {
        float l = 0.0f, r = 0.0f;
        ReadStereoFrame(data + static_cast<size_t>(i) * fmt->nBlockAlign, fmt, l, r);
        srcStereo.push_back(l);
        srcStereo.push_back(r);
    }

    std::lock_guard<std::mutex> lock(q.mtx);

    if (fmt->nSamplesPerSec == kOutSampleRate) {
        q.data.insert(q.data.end(), srcStereo.begin(), srcStereo.end());
        return;
    }

    const size_t srcFrameCount = srcStereo.size() / 2;
    if (srcFrameCount == 0) return;
    if (srcFrameCount == 1) {
        q.data.push_back(srcStereo[0]);
        q.data.push_back(srcStereo[1]);
        return;
    }

    const double ratio = static_cast<double>(fmt->nSamplesPerSec) /
                         static_cast<double>(kOutSampleRate);
    for (double srcPos = 0.0; srcPos < static_cast<double>(srcFrameCount - 1); srcPos += ratio) {
        const size_t i0 = static_cast<size_t>(srcPos);
        const double frac = srcPos - static_cast<double>(i0);

        const float l = static_cast<float>(
            srcStereo[i0 * 2] * (1.0 - frac) +
            srcStereo[(i0 + 1) * 2] * frac);
        const float r = static_cast<float>(
            srcStereo[i0 * 2 + 1] * (1.0 - frac) +
            srcStereo[(i0 + 1) * 2 + 1] * frac);

        q.data.push_back(l);
        q.data.push_back(r);
    }
}

static void ClearQueue(SampleQueue& q) {
    std::lock_guard<std::mutex> lock(q.mtx);
    q.data.clear();
}

static void RenderCaptureThreadProc() {
    HRESULT comHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool comOk = SUCCEEDED(comHr) || comHr == RPC_E_CHANGED_MODE;

    DWORD mmcssTaskIndex = 0;
    HANDLE mmcssHandle = AvSetMmThreadCharacteristicsW(L"Pro Audio", &mmcssTaskIndex);

    while (WaitForSingleObject(g_state.renderStopEvent, 5) != WAIT_OBJECT_0) {
        if (g_state.recState.load() != 1) {
            ClearQueue(g_state.sysQueue);
            UINT32 drainPacket = 0;
            if (SUCCEEDED(g_state.renderCapture->GetNextPacketSize(&drainPacket))) {
                while (drainPacket != 0) {
                    BYTE* drainData = nullptr;
                    UINT32 drainFrames = 0;
                    DWORD drainFlags = 0;
                    if (FAILED(g_state.renderCapture->GetBuffer(
                            &drainData, &drainFrames, &drainFlags, nullptr, nullptr))) break;
                    g_state.renderCapture->ReleaseBuffer(drainFrames);
                    if (FAILED(g_state.renderCapture->GetNextPacketSize(&drainPacket))) break;
                }
            }
            Sleep(5);
            continue;
        }

        BYTE* pData = nullptr;
        UINT32 numFrames = 0;
        UINT32 packetLength = 0;
        DWORD flags = 0;

        HRESULT hr = g_state.renderCapture->GetNextPacketSize(&packetLength);
        if (FAILED(hr)) continue;

        while (packetLength != 0) {
            hr = g_state.renderCapture->GetBuffer(
                &pData, &numFrames, &flags, nullptr, nullptr);
            if (FAILED(hr)) break;

            if (numFrames > 0) {
                if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                    std::vector<BYTE> silence(
                        static_cast<size_t>(numFrames) * g_state.renderFormat->nBlockAlign, 0);
                    PushResampled(g_state.sysQueue, silence.data(), numFrames, g_state.renderFormat);
                    g_state.sysLevel.store(0.0f);
                } else {
                    PushResampled(g_state.sysQueue, pData, numFrames, g_state.renderFormat);
                    g_state.sysLevel.store(CalculatePeak(
                        pData, numFrames, g_state.renderFormat));
                }
            }

            g_state.renderCapture->ReleaseBuffer(numFrames);
            hr = g_state.renderCapture->GetNextPacketSize(&packetLength);
            if (FAILED(hr)) break;
        }
    }

    if (comOk && comHr != RPC_E_CHANGED_MODE) CoUninitialize();
    if (mmcssHandle) AvRevertMmThreadCharacteristics(mmcssHandle);
}

static void MicCaptureThreadProc() {
    HRESULT comHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool comOk = SUCCEEDED(comHr) || comHr == RPC_E_CHANGED_MODE;

    DWORD mmcssTaskIndex = 0;
    HANDLE mmcssHandle = AvSetMmThreadCharacteristicsW(L"Pro Audio", &mmcssTaskIndex);

    while (WaitForSingleObject(g_state.micStopEvent, 5) != WAIT_OBJECT_0) {
        if (g_state.recState.load() != 1) {
            ClearQueue(g_state.micQueue);
            UINT32 drainPacket = 0;
            if (SUCCEEDED(g_state.micCapture->GetNextPacketSize(&drainPacket))) {
                while (drainPacket != 0) {
                    BYTE* drainData = nullptr;
                    UINT32 drainFrames = 0;
                    DWORD drainFlags = 0;
                    if (FAILED(g_state.micCapture->GetBuffer(
                            &drainData, &drainFrames, &drainFlags, nullptr, nullptr))) break;
                    g_state.micCapture->ReleaseBuffer(drainFrames);
                    if (FAILED(g_state.micCapture->GetNextPacketSize(&drainPacket))) break;
                }
            }
            Sleep(5);
            continue;
        }

        BYTE* pData = nullptr;
        UINT32 numFrames = 0;
        UINT32 packetLength = 0;
        DWORD flags = 0;

        HRESULT hr = g_state.micCapture->GetNextPacketSize(&packetLength);
        if (FAILED(hr)) continue;

        while (packetLength != 0) {
            hr = g_state.micCapture->GetBuffer(
                &pData, &numFrames, &flags, nullptr, nullptr);
            if (FAILED(hr)) break;

            if (numFrames > 0) {
                if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                    std::vector<BYTE> silence(
                        static_cast<size_t>(numFrames) * g_state.micFormat->nBlockAlign, 0);
                    PushResampled(g_state.micQueue, silence.data(), numFrames, g_state.micFormat);
                    g_state.micLevel.store(0.0f);
                } else {
                    PushResampled(g_state.micQueue, pData, numFrames, g_state.micFormat);
                    g_state.micLevel.store(CalculatePeak(
                        pData, numFrames, g_state.micFormat));
                }
            }

            g_state.micCapture->ReleaseBuffer(numFrames);
            hr = g_state.micCapture->GetNextPacketSize(&packetLength);
            if (FAILED(hr)) break;
        }
    }

    if (comOk && comHr != RPC_E_CHANGED_MODE) CoUninitialize();
    if (mmcssHandle) AvRevertMmThreadCharacteristics(mmcssHandle);
}

static void MixerThreadProc() {
    std::vector<float> chunk;

    LARGE_INTEGER freq;
    QueryPerformanceFrequency(&freq);
    LARGE_INTEGER lastTick;
    QueryPerformanceCounter(&lastTick);
    double frameRemainder = 0.0;

    while (g_state.mixerRunning.load()) {
        Sleep(10);

        if (g_state.recState.load() != 1) {
            ClearQueue(g_state.sysQueue);
            ClearQueue(g_state.micQueue);
            QueryPerformanceCounter(&lastTick);
            frameRemainder = 0.0;
            continue;
        }
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        double elapsedSec = static_cast<double>(now.QuadPart - lastTick.QuadPart) /
                             static_cast<double>(freq.QuadPart);
        lastTick = now;

        double framesNeededExact = elapsedSec * kOutSampleRate + frameRemainder;
        size_t framesNeeded = static_cast<size_t>(framesNeededExact);
        frameRemainder = framesNeededExact - static_cast<double>(framesNeeded);
        framesNeeded = std::min(framesNeeded, kMaxMixerFramesPerPass);

        if (framesNeeded == 0) continue;

        const float micVol = g_state.micMuted.load()
            ? 0.0f : g_state.micVolume.load();
        const float sysVol = g_state.sysMuted.load()
            ? 0.0f : g_state.sysVolume.load();

        chunk.clear();
        chunk.reserve(framesNeeded * kOutChannels);

        {
            std::scoped_lock lock(g_state.sysQueue.mtx, g_state.micQueue.mtx);

            const size_t nSys = std::min(framesNeeded, g_state.sysQueue.data.size() / 2);
            const size_t nMic = std::min(framesNeeded, g_state.micQueue.data.size() / 2);

            for (size_t frame = 0; frame < framesNeeded; ++frame) {
                float sL = 0.0f, sR = 0.0f;
                float mL = 0.0f, mR = 0.0f;

                if (frame < nSys) {
                    sL = g_state.sysQueue.data.front(); g_state.sysQueue.data.pop_front();
                    sR = g_state.sysQueue.data.front(); g_state.sysQueue.data.pop_front();
                }
                if (frame < nMic) {
                    mL = g_state.micQueue.data.front(); g_state.micQueue.data.pop_front();
                    mR = g_state.micQueue.data.front(); g_state.micQueue.data.pop_front();
                }

                chunk.push_back(std::clamp(sL * sysVol + mL * micVol, -1.0f, 1.0f));
                chunk.push_back(std::clamp(sR * sysVol + mR * micVol, -1.0f, 1.0f));
            }
        }

        if (!chunk.empty()) {
            std::lock_guard<std::mutex> wlock(g_state.wavMutex);
            if (g_state.wavFile) {
                fwrite(chunk.data(), sizeof(float), chunk.size(), g_state.wavFile);
                g_state.writtenFrames += chunk.size() / kOutChannels;
            }
        }
    }
}

static HRESULT SetupDevice(EDataFlow flow, bool loopback,
                            IMMDevice** outDevice, IAudioClient** outClient,
                            IAudioCaptureClient** outCapture, WAVEFORMATEX** outFormat) {
    if (!outDevice || !outClient || !outCapture || !outFormat || !g_state.enumerator)
        return E_INVALIDARG;

    *outDevice = nullptr;
    *outClient = nullptr;
    *outCapture = nullptr;
    *outFormat = nullptr;

    HRESULT hr = g_state.enumerator->GetDefaultAudioEndpoint(
        flow, eConsole, outDevice);
    if (FAILED(hr)) return hr;

    hr = (*outDevice)->Activate(
        __uuidof(IAudioClient), CLSCTX_ALL, nullptr,
        reinterpret_cast<void**>(outClient));
    if (FAILED(hr)) goto fail;

    hr = (*outClient)->GetMixFormat(outFormat);
    if (FAILED(hr)) goto fail;

    {
        DWORD streamFlags = loopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0;

        const REFERENCE_TIME hnsBufferDuration = loopback ? (200 * 10000) : (20 * 10000);

        hr = (*outClient)->Initialize(
            AUDCLNT_SHAREMODE_SHARED, streamFlags,
            hnsBufferDuration, 0, *outFormat, nullptr);
    }
    if (FAILED(hr)) goto fail;

    hr = (*outClient)->GetService(
        __uuidof(IAudioCaptureClient),
        reinterpret_cast<void**>(outCapture));
    if (FAILED(hr)) goto fail;

    return S_OK;

fail:
    if (*outCapture) { (*outCapture)->Release(); *outCapture = nullptr; }
    if (*outClient) { (*outClient)->Release(); *outClient = nullptr; }
    if (*outDevice) { (*outDevice)->Release(); *outDevice = nullptr; }
    if (*outFormat) { CoTaskMemFree(*outFormat); *outFormat = nullptr; }
    return hr;
}

static void ReleaseDevice(IMMDevice*& device, IAudioClient*& client,
                          IAudioCaptureClient*& capture,
                          WAVEFORMATEX*& format) {
    if (capture) { capture->Release(); capture = nullptr; }
    if (client) { client->Release(); client = nullptr; }
    if (device) { device->Release(); device = nullptr; }
    if (format) { CoTaskMemFree(format); format = nullptr; }
}

// ================= توابع خروجی DLL =================

AE_API int AE_Initialize() {
    if (g_state.initialized.load()) return AE_OK;

    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (hr == RPC_E_CHANGED_MODE) {
        g_state.comInitialized = false;
    } else if (FAILED(hr)) {
        return AE_ERR_INIT;
    } else {
        g_state.comInitialized = true;
    }

    hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&g_state.enumerator));

    if (FAILED(hr)) {
        if (g_state.comInitialized) {
            CoUninitialize();
            g_state.comInitialized = false;
        }
        return AE_ERR_INIT;
    }

    QueryPerformanceFrequency(&g_state.qpcFreq);
    g_state.initialized.store(true);
    return AE_OK;
}

AE_API void AE_Shutdown() {
    if (g_state.recState.load() != 0) {
        AE_StopRecording();
    }

    if (g_state.enumerator) {
        g_state.enumerator->Release();
        g_state.enumerator = nullptr;
    }

    if (g_state.comInitialized) {
        CoUninitialize();
        g_state.comInitialized = false;
    }

    g_state.initialized.store(false);
}

AE_API int AE_StartRecording(const wchar_t* outputWavPathUtf16, int sampleRate) {
    if (!g_state.initialized.load()) return AE_ERR_INIT;
    if (g_state.recState.load() != 0) return AE_ERR_ALREADY_RUNNING;
    if (!outputWavPathUtf16 || !*outputWavPathUtf16) return AE_ERR_FILE;
    if (sampleRate != 0 && sampleRate != kOutSampleRate) return AE_ERR_FILE;

    HRESULT hr = SetupDevice(
        eRender, true,
        &g_state.renderDevice, &g_state.renderClient,
        &g_state.renderCapture, &g_state.renderFormat);
    if (FAILED(hr)) {
        ReleaseDevice(g_state.renderDevice, g_state.renderClient,
                       g_state.renderCapture, g_state.renderFormat);
        return AE_ERR_DEVICE;
    }

    hr = SetupDevice(
        eCapture, false,
        &g_state.micDevice, &g_state.micClient,
        &g_state.micCapture, &g_state.micFormat);
    if (FAILED(hr)) {
        ReleaseDevice(g_state.renderDevice, g_state.renderClient,
                       g_state.renderCapture, g_state.renderFormat);
        ReleaseDevice(g_state.micDevice, g_state.micClient,
                       g_state.micCapture, g_state.micFormat);
        return AE_ERR_DEVICE;
    }

    FILE* f = nullptr;
    if (_wfopen_s(&f, outputWavPathUtf16, L"wb") != 0 || !f) {
        ReleaseDevice(g_state.renderDevice, g_state.renderClient,
                       g_state.renderCapture, g_state.renderFormat);
        ReleaseDevice(g_state.micDevice, g_state.micClient,
                       g_state.micCapture, g_state.micFormat);
        return AE_ERR_FILE;
    }

    WriteWavHeaderPlaceholder(f);
    g_state.wavFile = f;
    g_state.writtenFrames = 0;

    ClearQueue(g_state.sysQueue);
    ClearQueue(g_state.micQueue);
    g_state.sysLevel.store(0.0f);
    g_state.micLevel.store(0.0f);

    g_state.renderStopEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    g_state.micStopEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);

    if (!g_state.renderStopEvent || !g_state.micStopEvent) {
        if (g_state.renderStopEvent) {
            CloseHandle(g_state.renderStopEvent);
            g_state.renderStopEvent = nullptr;
        }
        if (g_state.micStopEvent) {
            CloseHandle(g_state.micStopEvent);
            g_state.micStopEvent = nullptr;
        }
        fclose(f);
        g_state.wavFile = nullptr;
        ReleaseDevice(g_state.renderDevice, g_state.renderClient,
                       g_state.renderCapture, g_state.renderFormat);
        ReleaseDevice(g_state.micDevice, g_state.micClient,
                       g_state.micCapture, g_state.micFormat);
        return AE_ERR_INIT;
    }

    hr = g_state.renderClient->Start();
    if (FAILED(hr)) goto start_fail;

    hr = g_state.micClient->Start();
    if (FAILED(hr)) {
        g_state.renderClient->Stop();
        goto start_fail;
    }

    g_state.recState.store(1);

    try {
        g_state.renderThread = std::thread(RenderCaptureThreadProc);
        g_state.micThread = std::thread(MicCaptureThreadProc);
        g_state.mixerRunning.store(true);
        g_state.mixerThread = std::thread(MixerThreadProc);
    } catch (...) {
        g_state.recState.store(0);
        g_state.mixerRunning.store(false);
        if (g_state.renderStopEvent) SetEvent(g_state.renderStopEvent);
        if (g_state.micStopEvent) SetEvent(g_state.micStopEvent);
        if (g_state.renderThread.joinable()) g_state.renderThread.join();
        if (g_state.micThread.joinable()) g_state.micThread.join();
        if (g_state.mixerThread.joinable()) g_state.mixerThread.join();
        g_state.renderClient->Stop();
        g_state.micClient->Stop();
        goto start_fail;
    }

    QueryPerformanceCounter(&g_state.startTime);
    g_state.pausedAccum.QuadPart = 0;
    g_state.pauseStartTime.QuadPart = 0;
    return AE_OK;

start_fail:
    if (g_state.renderStopEvent) SetEvent(g_state.renderStopEvent);
    if (g_state.micStopEvent) SetEvent(g_state.micStopEvent);
    if (g_state.renderThread.joinable()) g_state.renderThread.join();
    if (g_state.micThread.joinable()) g_state.micThread.join();

    g_state.mixerRunning.store(false);
    if (g_state.mixerThread.joinable()) g_state.mixerThread.join();

    if (g_state.renderClient) g_state.renderClient->Stop();
    if (g_state.micClient) g_state.micClient->Stop();

    if (g_state.renderStopEvent) {
        CloseHandle(g_state.renderStopEvent);
        g_state.renderStopEvent = nullptr;
    }
    if (g_state.micStopEvent) {
        CloseHandle(g_state.micStopEvent);
        g_state.micStopEvent = nullptr;
    }

    {
        std::lock_guard<std::mutex> wlock(g_state.wavMutex);
        if (g_state.wavFile) {
            fclose(g_state.wavFile);
            g_state.wavFile = nullptr;
        }
    }

    ReleaseDevice(g_state.renderDevice, g_state.renderClient,
                   g_state.renderCapture, g_state.renderFormat);
    ReleaseDevice(g_state.micDevice, g_state.micClient,
                   g_state.micCapture, g_state.micFormat);
    return AE_ERR_DEVICE;
}

AE_API int AE_StopRecording() {
    if (g_state.recState.load() == 0) return AE_ERR_NOT_RUNNING;

    g_state.recState.store(0);

    if (g_state.renderStopEvent) SetEvent(g_state.renderStopEvent);
    if (g_state.micStopEvent) SetEvent(g_state.micStopEvent);

    if (g_state.renderThread.joinable()) g_state.renderThread.join();
    if (g_state.micThread.joinable()) g_state.micThread.join();

    g_state.mixerRunning.store(false);
    if (g_state.mixerThread.joinable()) g_state.mixerThread.join();

    if (g_state.renderClient) g_state.renderClient->Stop();
    if (g_state.micClient) g_state.micClient->Stop();

    if (g_state.renderStopEvent) {
        CloseHandle(g_state.renderStopEvent);
        g_state.renderStopEvent = nullptr;
    }
    if (g_state.micStopEvent) {
        CloseHandle(g_state.micStopEvent);
        g_state.micStopEvent = nullptr;
    }

    {
        std::lock_guard<std::mutex> wlock(g_state.wavMutex);
        if (g_state.wavFile) {
            PatchWavHeaderAndClose(g_state.wavFile, g_state.writtenFrames);
            g_state.wavFile = nullptr;
        }
    }

    ReleaseDevice(g_state.renderDevice, g_state.renderClient,
                   g_state.renderCapture, g_state.renderFormat);
    ReleaseDevice(g_state.micDevice, g_state.micClient,
                   g_state.micCapture, g_state.micFormat);

    ClearQueue(g_state.sysQueue);
    ClearQueue(g_state.micQueue);
    g_state.sysLevel.store(0.0f);
    g_state.micLevel.store(0.0f);

    return AE_OK;
}

AE_API void AE_Pause() {
    if (g_state.recState.load() == 1) {
        g_state.recState.store(2);
        QueryPerformanceCounter(&g_state.pauseStartTime);
    }
}

AE_API void AE_Resume() {
    if (g_state.recState.load() == 2) {
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        g_state.pausedAccum.QuadPart += (now.QuadPart - g_state.pauseStartTime.QuadPart);
        g_state.recState.store(1);
    }
}

AE_API int AE_GetState() { return g_state.recState.load(); }

AE_API void AE_SetMicVolume(float v) { g_state.micVolume.store(std::clamp(v, 0.0f, 2.0f)); }
AE_API void AE_SetSystemVolume(float v) { g_state.sysVolume.store(std::clamp(v, 0.0f, 2.0f)); }
AE_API void AE_SetMicMuted(int muted) { g_state.micMuted.store(muted != 0); }
AE_API void AE_SetSystemMuted(int muted) { g_state.sysMuted.store(muted != 0); }

AE_API void AE_GetLevels(float* micLevel, float* systemLevel) {
    if (micLevel) *micLevel = g_state.micMuted.load() ? 0.0f : g_state.micLevel.load();
    if (systemLevel) *systemLevel = g_state.sysMuted.load() ? 0.0f : g_state.sysLevel.load();
}

AE_API long long AE_GetElapsedMs() {
    if (g_state.recState.load() == 0) return 0;
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    LARGE_INTEGER paused = g_state.pausedAccum;
    if (g_state.recState.load() == 2) {
        paused.QuadPart += now.QuadPart - g_state.pauseStartTime.QuadPart;
    }

    LARGE_INTEGER elapsed;
    elapsed.QuadPart = now.QuadPart - g_state.startTime.QuadPart - paused.QuadPart;
    if (elapsed.QuadPart < 0) elapsed.QuadPart = 0;
    return (long long)((double)elapsed.QuadPart * 1000.0 /
                       (double)g_state.qpcFreq.QuadPart);
}

#pragma once

#include <napi.h>
#include "recorder.h"

class RecorderWrapper : public Napi::ObjectWrap<RecorderWrapper> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports);
    RecorderWrapper(const Napi::CallbackInfo& info);
    ~RecorderWrapper();

private:
    static Napi::FunctionReference constructor;
    
    // JS暴露的方法
    Napi::Value Start(const Napi::CallbackInfo& info);
    Napi::Value Stop(const Napi::CallbackInfo& info);
    Napi::Value Pause(const Napi::CallbackInfo& info);
    Napi::Value Resume(const Napi::CallbackInfo& info);
    Napi::Value IsRecording(const Napi::CallbackInfo& info);
    Napi::Value SetOutputPath(const Napi::CallbackInfo& info);
    Napi::Value GetCurrentMicrophoneApp(const Napi::CallbackInfo& info);
    Napi::Value SetMicNoiseReduction(const Napi::CallbackInfo& info);
    Napi::Value SetSpeakerNoiseReduction(const Napi::CallbackInfo& info);
    
    AudioRecorder* recorder_;
}; 
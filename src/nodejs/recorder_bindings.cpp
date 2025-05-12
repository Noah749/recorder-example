#include <napi.h>
#include "../../include/recorder.h"
#include <iostream>

class RecorderWrapper : public Napi::ObjectWrap<RecorderWrapper> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports) {
        Napi::Function func = DefineClass(env, "Recorder", {
            InstanceMethod("start", &RecorderWrapper::Start),
            InstanceMethod("stop", &RecorderWrapper::Stop),
            InstanceMethod("pause", &RecorderWrapper::Pause),
            InstanceMethod("resume", &RecorderWrapper::Resume),
            InstanceMethod("isRecording", &RecorderWrapper::IsRecording),
            InstanceMethod("setOutputPath", &RecorderWrapper::SetOutputPath),
            InstanceMethod("getCurrentMicrophoneApp", &RecorderWrapper::GetCurrentMicrophoneApp)
        });

        exports.Set("Recorder", func);
        return exports;
    }

    RecorderWrapper(const Napi::CallbackInfo& info) : Napi::ObjectWrap<RecorderWrapper>(info) {
        try {
            recorder_ = new AudioRecorder();
            if (!recorder_) {
                throw std::runtime_error("Failed to create AudioRecorder");
            }
        } catch (const std::exception& e) {
            Napi::Error::New(info.Env(), e.what()).ThrowAsJavaScriptException();
        }
    }

    ~RecorderWrapper() {
        if (recorder_) {
            try {
                delete recorder_;
                recorder_ = nullptr;
            } catch (const std::exception& e) {
            }
        }
    }

private:
    void CheckRecorder(const Napi::CallbackInfo& info) {
        if (!recorder_) {
            Napi::Error::New(info.Env(), "AudioRecorder is not initialized").ThrowAsJavaScriptException();
        }
    }

    Napi::Value Start(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        bool success = recorder_->Start();
        return Napi::Boolean::New(env, success);
    }

    void Stop(const Napi::CallbackInfo& info) {
        CheckRecorder(info);
        recorder_->Stop();
    }

    void Pause(const Napi::CallbackInfo& info) {
        CheckRecorder(info);
        recorder_->Pause();
    }

    void Resume(const Napi::CallbackInfo& info) {
        CheckRecorder(info);
        recorder_->Resume();
    }

    Napi::Value IsRecording(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        bool isRecording = recorder_->IsRecording();
        return Napi::Boolean::New(env, isRecording);
    }

    void SetOutputPath(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        
        if (info.Length() < 1 || !info[0].IsString()) {
            Napi::TypeError::New(env, "String expected").ThrowAsJavaScriptException();
            return;
        }

        try {
            std::string path = info[0].As<Napi::String>().Utf8Value();
            recorder_->SetOutputPath(path);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
        }
    }

    Napi::Value GetCurrentMicrophoneApp(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        try {
            std::string appName = recorder_->GetCurrentMicrophoneApp();
            return Napi::String::New(env, appName);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return Napi::String::New(env, "");
        }
    }

    AudioRecorder* recorder_ = nullptr;
};

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    return RecorderWrapper::Init(env, exports);
}

NODE_API_MODULE(recorder, Init) 
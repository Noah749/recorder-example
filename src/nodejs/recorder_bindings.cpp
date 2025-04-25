#include <napi.h>
#include "../recorder.h"
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
        std::cout << "Creating RecorderWrapper..." << std::endl;
        try {
            recorder_ = new AudioRecorder();
            if (!recorder_) {
                throw std::runtime_error("Failed to create AudioRecorder");
            }
            std::cout << "AudioRecorder created successfully" << std::endl;
        } catch (const std::exception& e) {
            std::cerr << "Error creating AudioRecorder: " << e.what() << std::endl;
            Napi::Error::New(info.Env(), e.what()).ThrowAsJavaScriptException();
        }
    }

    ~RecorderWrapper() {
        std::cout << "Destroying RecorderWrapper..." << std::endl;
        if (recorder_) {
            try {
                delete recorder_;
                recorder_ = nullptr;
                std::cout << "AudioRecorder destroyed successfully" << std::endl;
            } catch (const std::exception& e) {
                std::cerr << "Error destroying AudioRecorder: " << e.what() << std::endl;
            }
        }
    }

private:
    void CheckRecorder(const Napi::CallbackInfo& info) {
        if (!recorder_) {
            std::cerr << "AudioRecorder is not initialized" << std::endl;
            Napi::Error::New(info.Env(), "AudioRecorder is not initialized").ThrowAsJavaScriptException();
        }
    }

    Napi::Value Start(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        std::cout << "Starting recording..." << std::endl;
        CheckRecorder(info);
        bool success = recorder_->Start();
        std::cout << "Start recording result: " << (success ? "success" : "failed") << std::endl;
        return Napi::Boolean::New(env, success);
    }

    void Stop(const Napi::CallbackInfo& info) {
        std::cout << "Stopping recording..." << std::endl;
        CheckRecorder(info);
        recorder_->Stop();
    }

    void Pause(const Napi::CallbackInfo& info) {
        std::cout << "Pausing recording..." << std::endl;
        recorder_->Pause();
    }

    void Resume(const Napi::CallbackInfo& info) {
        std::cout << "Resuming recording..." << std::endl;
        CheckRecorder(info);
        recorder_->Resume();
    }

    Napi::Value IsRecording(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);

        bool isRecording = recorder_->IsRecording();
        std::cout << "Is recording: " << (isRecording ? "yes" : "no") << std::endl;
        return Napi::Boolean::New(env, isRecording);

    }

    void SetOutputPath(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        
        if (info.Length() < 1 || !info[0].IsString()) {
            std::cerr << "Invalid output path argument" << std::endl;
            Napi::TypeError::New(env, "String expected").ThrowAsJavaScriptException();
            return;
        }

        try {
            std::string path = info[0].As<Napi::String>().Utf8Value();
            std::cout << "Setting output path to: " << path << std::endl;
            recorder_->SetOutputPath(path);
            std::cout << "Output path set successfully" << std::endl;
        } catch (const std::exception& e) {
            std::cerr << "Error setting output path: " << e.what() << std::endl;
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
        }
    }

    Napi::Value GetCurrentMicrophoneApp(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        try {
            std::string appName = recorder_->GetCurrentMicrophoneApp();
            std::cout << "Current microphone app: " << appName << std::endl;
            return Napi::String::New(env, appName);
        } catch (const std::exception& e) {
            std::cerr << "Error getting current microphone app: " << e.what() << std::endl;
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
#include "node_recorder.h"
#include "logger.h"

Napi::FunctionReference RecorderWrapper::constructor;

Napi::Object RecorderWrapper::Init(Napi::Env env, Napi::Object exports) {
    Napi::HandleScope scope(env);

    Napi::Function func = DefineClass(env, "Recorder", {
        InstanceMethod("start", &RecorderWrapper::Start),
        InstanceMethod("stop", &RecorderWrapper::Stop),
        InstanceMethod("pause", &RecorderWrapper::Pause),
        InstanceMethod("resume", &RecorderWrapper::Resume),
        InstanceMethod("isRecording", &RecorderWrapper::IsRecording),
        InstanceMethod("setOutputPath", &RecorderWrapper::SetOutputPath),
        InstanceMethod("getCurrentMicrophoneApp", &RecorderWrapper::GetCurrentMicrophoneApp),
        InstanceMethod("setMicNoiseReduction", &RecorderWrapper::SetMicNoiseReduction),
        InstanceMethod("setSpeakerNoiseReduction", &RecorderWrapper::SetSpeakerNoiseReduction),
    });

    constructor = Napi::Persistent(func);
    constructor.SuppressDestruct();

    exports.Set("Recorder", func);
    return exports;
}

RecorderWrapper::RecorderWrapper(const Napi::CallbackInfo& info)
    : Napi::ObjectWrap<RecorderWrapper>(info) {
    Napi::Env env = info.Env();
    Napi::HandleScope scope(env);
    
    recorder_ = new AudioRecorder();
    Logger::info("创建 JS Recorder 实例");
}

RecorderWrapper::~RecorderWrapper() {
    Logger::info("销毁 JS Recorder 实例");
    delete recorder_;
}

Napi::Value RecorderWrapper::Start(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Logger::debug("JS 调用: start()");
    bool success = recorder_->Start();
    return Napi::Boolean::New(env, success);
}

Napi::Value RecorderWrapper::Stop(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Logger::debug("JS 调用: stop()");
    recorder_->Stop();
    return env.Undefined();
}

Napi::Value RecorderWrapper::Pause(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Logger::debug("JS 调用: pause()");
    recorder_->Pause();
    return env.Undefined();
}

Napi::Value RecorderWrapper::Resume(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Logger::debug("JS 调用: resume()");
    recorder_->Resume();
    return env.Undefined();
}

Napi::Value RecorderWrapper::IsRecording(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Logger::debug("JS 调用: isRecording()");
    bool recording = recorder_->IsRecording();
    return Napi::Boolean::New(env, recording);
}

Napi::Value RecorderWrapper::SetOutputPath(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsString()) {
        Logger::error("JS 调用 setOutputPath() 但参数类型错误");
        Napi::TypeError::New(env, "String expected").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    std::string path = info[0].As<Napi::String>().Utf8Value();
    Logger::debug("JS 调用: setOutputPath('%s')", path.c_str());
    recorder_->SetOutputPath(path);
    
    return env.Undefined();
}

Napi::Value RecorderWrapper::GetCurrentMicrophoneApp(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Logger::debug("JS 调用: getCurrentMicrophoneApp()");
    std::string app = recorder_->GetCurrentMicrophoneApp();
    return Napi::String::New(env, app);
}

Napi::Value RecorderWrapper::SetMicNoiseReduction(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Logger::error("JS 调用 setMicNoiseReduction() 但参数类型错误");
        Napi::TypeError::New(env, "Number expected").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    int level = info[0].As<Napi::Number>().Int32Value();
    Logger::debug("JS 调用: setMicNoiseReduction(%d)", level);
    recorder_->SetMicNoiseReduction(level);
    
    return env.Undefined();
}

Napi::Value RecorderWrapper::SetSpeakerNoiseReduction(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Logger::error("JS 调用 setSpeakerNoiseReduction() 但参数类型错误");
        Napi::TypeError::New(env, "Number expected").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    int level = info[0].As<Napi::Number>().Int32Value();
    Logger::debug("JS 调用: setSpeakerNoiseReduction(%d)", level);
    recorder_->SetSpeakerNoiseReduction(level);
    
    return env.Undefined();
} 
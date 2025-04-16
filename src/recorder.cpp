#include "recorder.h"
#include "logger.h"
#include "mac_recorder.h"

// 基础实现，后续会根据平台进行具体功能实现
AudioRecorder::AudioRecorder() 
    : isRecording_(false), 
      isPaused_(false), 
      micNoiseReductionLevel_(5), 
      speakerNoiseReductionLevel_(5),
      platformImpl_(nullptr) {
    // 初始化日志系统
    Logger::init();
    Logger::info("AudioRecorder 初始化");
    
    // 创建平台特定实现
#ifdef __APPLE__
    platformImpl_ = new MacRecorder(this);
    Logger::info("使用 macOS 录音实现");
#else
    Logger::warn("当前平台尚未实现录音功能");
#endif
}

AudioRecorder::~AudioRecorder() {
    Logger::info("AudioRecorder 销毁中");
    if (isRecording_) {
        Stop();
    }
    
    // 清理平台特定资源
    if (platformImpl_) {
#ifdef __APPLE__
        delete platformImpl_;
#endif
        platformImpl_ = nullptr;
    }
    
    Logger::shutdown();
}

bool AudioRecorder::Start() {
    Logger::info("开始录制请求");
    if (isRecording_ && !isPaused_) {
        Logger::warn("已经在录制中，忽略开始请求");
        return false;
    }
    
    // 使用平台实现
    bool success = false;
    if (platformImpl_) {
#ifdef __APPLE__
        success = platformImpl_->Start();
#endif
    } else {
        Logger::error("平台实现为空，无法开始录制");
        return false;
    }
    
    if (success) {
        isRecording_ = true;
        isPaused_ = false;
        Logger::info("录制状态设置为: 录制中");
    } else {
        Logger::error("平台录制启动失败");
    }
    
    return success;
}

void AudioRecorder::Stop() {
    Logger::info("停止录制请求");
    if (!isRecording_) {
        Logger::warn("未在录制中，忽略停止请求");
        return;
    }
    
    // 使用平台实现
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->Stop();
#endif
    }
    
    isRecording_ = false;
    isPaused_ = false;
    Logger::info("录制状态设置为: 已停止");
}

void AudioRecorder::Pause() {
    Logger::info("暂停录制请求");
    if (!isRecording_ || isPaused_) {
        Logger::warn("未在录制中或已暂停，忽略暂停请求");
        return;
    }
    
    // 使用平台实现
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->Pause();
#endif
    }
    
    isPaused_ = true;
    Logger::info("录制状态设置为: 已暂停");
}

void AudioRecorder::Resume() {
    Logger::info("恢复录制请求");
    if (!isRecording_ || !isPaused_) {
        Logger::warn("未在录制中或未暂停，忽略恢复请求");
        return;
    }
    
    // 使用平台实现
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->Resume();
#endif
    }
    
    isPaused_ = false;
    Logger::info("录制状态设置为: 录制中(恢复)");
}

bool AudioRecorder::IsRecording() const {
    bool status = isRecording_ && !isPaused_;
    Logger::debug("查询录制状态: %s", status ? "录制中" : "未录制");
    return status;
}

void AudioRecorder::SetOutputPath(const std::string& path) {
    Logger::info("设置输出路径: %s", path.c_str());
    outputPath_ = path;
    
    // 设置平台实现的输出路径
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->SetOutputPath(path);
#endif
    }
}

std::string AudioRecorder::GetCurrentMicrophoneApp() {
    Logger::info("获取当前占用麦克风的应用");
    
    if (platformImpl_) {
#ifdef __APPLE__
        return platformImpl_->GetCurrentMicrophoneApp();
#endif
    }
    
    return "Unknown Application";
}

void AudioRecorder::SetMicNoiseReduction(int level) {
    if (level < 0) level = 0;
    if (level > 10) level = 10;
    
    Logger::info("设置麦克风降噪级别: %d", level);
    micNoiseReductionLevel_ = level;
    
    // 设置平台实现的降噪级别
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->SetMicNoiseReduction(level);
#endif
    }
}

void AudioRecorder::SetSpeakerNoiseReduction(int level) {
    if (level < 0) level = 0;
    if (level > 10) level = 10;
    
    Logger::info("设置扬声器降噪级别: %d", level);
    speakerNoiseReductionLevel_ = level;
    
    // 设置平台实现的降噪级别
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->SetSpeakerNoiseReduction(level);
#endif
    }
}

// RecorderWrapper 实现
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
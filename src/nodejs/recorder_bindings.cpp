#include <napi.h>
#include <CoreAudio/CoreAudio.h>
#include "../logger.h"

// 声明测试函数
void TestMicRecorder();
void TestSystemCaptureRecorder();
void TestAudioEngine();

// 包装函数，确保在正确的上下文中执行
static Napi::Value TestMicRecorderWrapper(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    try {
        Logger::info("开始测试麦克风录音");
        TestMicRecorder();
        Logger::info("麦克风录音测试完成");
        return Napi::Boolean::New(env, true);
    } catch (const std::exception& e) {
        Logger::error("麦克风录音测试失败: {}", e.what());
        Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }
}

static Napi::Value TestSystemCaptureRecorderWrapper(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    try {
        Logger::info("开始测试系统音频捕获 - 初始化阶段");
        TestSystemCaptureRecorder();
        Logger::info("系统音频捕获测试完成");
        return Napi::Boolean::New(env, true);
    } catch (const std::exception& e) {
        Logger::error("系统音频捕获测试失败: {}", e.what());
        Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    } catch (...) {
        Logger::error("系统音频捕获测试失败: 未知错误");
        Napi::Error::New(env, "未知错误").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }
}

static Napi::Value TestAudioEngineWrapper(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    try {
        Logger::info("开始测试音频引擎");
        TestAudioEngine();
        Logger::info("音频引擎测试完成");
        return Napi::Boolean::New(env, true);
    } catch (const std::exception& e) {
        Logger::error("音频引擎测试失败: {}", e.what());
        Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    Logger::info("初始化 Node.js 模块");
    
    // 导出函数
    exports.Set("testMicRecorder", Napi::Function::New(env, TestMicRecorderWrapper));
    exports.Set("testSystemCaptureRecorder", Napi::Function::New(env, TestSystemCaptureRecorderWrapper));
    exports.Set("testAudioEngine", Napi::Function::New(env, TestAudioEngineWrapper));
    
    Logger::info("Node.js 模块初始化完成");
    return exports;
}

NODE_API_MODULE(meeting_recorder, Init) 
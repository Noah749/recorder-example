#pragma once

#include <napi.h>
#include <string>
#include <atomic>

// 前向声明
class MacRecorder;

class AudioRecorder {
public:
    AudioRecorder();
    ~AudioRecorder();

    // 开始录制
    bool Start();
    
    // 停止录制
    void Stop();
    
    // 暂停录制
    void Pause();
    
    // 恢复录制
    void Resume();
    
    // 是否正在录制
    bool IsRecording() const;
    
    // 设置输出文件路径
    void SetOutputPath(const std::string& path);
    
    // 获取当前占用麦克风的应用
    std::string GetCurrentMicrophoneApp();
    
    // 设置麦克风降噪级别 (0-10)
    void SetMicNoiseReduction(int level);
    
    // 设置扬声器降噪级别 (0-10)
    void SetSpeakerNoiseReduction(int level);

private:
    std::string outputPath_;
    std::atomic<bool> isRecording_;
    std::atomic<bool> isPaused_;
    int micNoiseReductionLevel_;
    int speakerNoiseReductionLevel_;
    
    // 平台相关实现的指针
    MacRecorder* platformImpl_;
};

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
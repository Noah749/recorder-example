#pragma once

#include <string>
#include <atomic>
#include <thread>
#include <mutex>
#include <vector>
#include <AVFoundation/AVFoundation.h>

// 前向声明
class AudioRecorder;

// macOS平台的实现类
class MacRecorder {
public:
    MacRecorder(AudioRecorder* recorder);
    ~MacRecorder();

    bool Start();
    void Stop();
    void Pause();
    void Resume();
    
    bool IsRunning() const;
    
    void SetOutputPath(const std::string& path);
    std::string GetCurrentMicrophoneApp();
    
    // 设置系统音频音量
    void SetSystemAudioVolume(float volume);
    // 设置麦克风音量
    void SetMicrophoneVolume(float volume);

private:
    // 初始化音频会话和设备
    bool InitializeAudio();
    
    // 清理音频资源
    void CleanupAudio();
    
    // 音频录制回调
    void HandleAudioBuffer(AVAudioPCMBuffer* buffer);
    
    // 写入音频文件
    bool OpenAudioFile();
    void CloseAudioFile();
    void WriteAudioDataToFile(AVAudioPCMBuffer* buffer);
    
    // 获取当前使用麦克风的应用
    void UpdateCurrentMicrophoneApp();
    
    // 成员变量
    AudioRecorder* recorder_;
    std::string outputPath_;
    std::atomic<bool> running_;
    std::atomic<bool> paused_;
    std::mutex audioMutex_;
    
    // AVAudioEngine 相关
    AVAudioEngine* audioEngine_;
    AVAudioInputNode* inputNode_;  // 麦克风输入节点
    AVAudioInputNode* systemNode_; // 系统音频输入节点
    AVAudioMixerNode* mixerNode_;  // 混合节点
    AVAudioFormat* audioFormat_;
    
    // 音量控制
    float systemAudioVolume_;
    float microphoneVolume_;
    
    // 文件写入
    AVAudioFile* audioFile_;
    bool fileOpen_;
    
    // 当前使用麦克风的应用
    std::string currentMicApp_;
}; 
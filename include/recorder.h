#pragma once

#include <string>

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

private:
    bool isRecording_;
    bool isPaused_;
    std::string outputPath_;
    
    // 平台特定实现
    MacRecorder* platformImpl_;
}; 
#pragma once

#include <string>
#include <atomic>
#include <thread>
#include <mutex>
#include <vector>
#include <AudioToolbox/AudioToolbox.h>

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
    
    void SetMicNoiseReduction(int level);
    void SetSpeakerNoiseReduction(int level);

private:
    // 初始化音频会话和设备
    bool InitializeAudio();
    
    // 清理音频资源
    void CleanupAudio();
    
    // 音频录制回调
    static OSStatus RecordingCallback(void* inRefCon, 
                                     AudioUnitRenderActionFlags* ioActionFlags,
                                     const AudioTimeStamp* inTimeStamp,
                                     UInt32 inBusNumber,
                                     UInt32 inNumberFrames,
                                     AudioBufferList* ioData);

    // 实际处理音频数据的内部方法
    OSStatus HandleRecordingCallback(UInt32 inNumberFrames);
    
    // 写入音频文件
    bool OpenAudioFile();
    void CloseAudioFile();
    void WriteAudioDataToFile(const void* data, UInt32 numBytes);
    
    // 获取当前使用麦克风的应用
    void UpdateCurrentMicrophoneApp();
    
    // 成员变量
    AudioRecorder* recorder_;
    std::string outputPath_;
    std::atomic<bool> running_;
    std::atomic<bool> paused_;
    std::mutex audioMutex_;
    
    // 音频设备和格式
    AudioUnit audioUnit_;
    AudioStreamBasicDescription audioFormat_;
    
    // 噪声消除设置
    int micNoiseReductionLevel_;
    int speakerNoiseReductionLevel_;
    
    // 文件写入
    ExtAudioFileRef audioFile_;
    bool fileOpen_;
    
    // 当前使用麦克风的应用
    std::string currentMicApp_;
    
    // 音频处理缓冲区
    AudioBufferList* inputBuffer_;
    std::vector<Float32> processingBuffer_;
}; 
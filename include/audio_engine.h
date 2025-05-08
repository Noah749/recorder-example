#pragma once

#import <AVFoundation/AVFoundation.h>
#import <AVFAudio/AVAudioSinkNode.h>
#include "audio_system_capture.h"
#include "aggregate_device.h"
#include "logger.h"
#include <memory>
#include <string>

class AudioEngine {
public:
    AudioEngine(AggregateDevice* aggregateDevice);
    ~AudioEngine();
    
    // 初始化音频引擎
    bool Initialize();
    
    // 准备音频引擎
    bool Prepare();
    
    // 启动音频引擎
    bool Start();
    
    // 暂停音频引擎
    void Pause();
    
    // 恢复音频引擎
    void Resume();
    
    // 停止音频引擎
    void Stop();
    
    // 设置输出文件路径
    void SetOutputPaths(const std::string& micPath, 
                       const std::string& sourcePath,
                       const std::string& mixPath);
    
    // 获取音频引擎状态
    bool IsRunning() const;
    
private:
    // 创建音频节点
    bool CreateNodes();
    
    // 连接音频节点
    bool ConnectNodes();
    
    // 创建音频文件
    bool CreateAudioFiles();
    
    // 清理音频文件
    void CleanupAudioFiles();
    
    // 设置音频格式
    void SetupAudioFormats();
    
private:
    AVAudioEngine* audioEngine_;
    AVAudioInputNode* inputNode_;
    AVAudioSourceNode* sourceNode_;
    AVAudioMixerNode* mixerNode_;
    AVAudioSinkNode* sinkNode_;
    AVAudioUnit* aecAudioUnit_;
    
    AudioSystemCapture* systemCapture_;
    AggregateDevice* aggregateDevice_;
    
    AVAudioFormat* standardFormat_;
    AVAudioFormat* micFormat_;
    AVAudioFormat* mixerOutputFormat_;
    
    ExtAudioFileRef micAudioFile_;
    ExtAudioFileRef sourceAudioFile_;
    ExtAudioFileRef mixAudioFile_;
    
    std::string micOutputPath_;
    std::string sourceOutputPath_;
    std::string mixOutputPath_;
    
    bool isRunning_;
    bool isPaused_;
}; 
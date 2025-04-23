#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#endif

#include "audio_system_capture.h"
#include "audio_device_manager.h"

#ifdef __OBJC__
@class MacSystemAudioNode;
@class AVAudioEngine;
@class AVAudioMixerNode;
@class AVAudioFormat;
@class NSError;
#endif

// 前向声明
class AudioRecorder;

// macOS平台的实现类
class MacRecorder {
public:
    MacRecorder();
    explicit MacRecorder(AudioRecorder* recorder);
    ~MacRecorder();

    bool Start();
    void Stop();
    bool IsRecording() const;
    
    void Pause();
    void Resume();
    
    bool IsRunning() const;
    
    void SetOutputPath(const std::string& path);
    std::string GetCurrentMicrophoneApp() const;
    
    // 设置系统音频音量
    void SetSystemAudioVolume(float volume);
    // 设置麦克风音量
    void SetMicrophoneVolume(float volume);

private:
    AudioRecorder* recorder_;
    std::string outputPath_;
    std::atomic<bool> running_;
    std::atomic<bool> paused_;
    std::mutex audioMutex_;
    
    float systemAudioVolume_;
    float microphoneVolume_;
    std::string currentMicApp_;
    
    AudioSystemCapture* systemCapture_;
    AudioDeviceManager* deviceManager_;
    bool isRecording_;

#ifdef __OBJC__
    AVAudioEngine* audioEngine_;
#else
    void* audioEngine_;
#endif
}; 
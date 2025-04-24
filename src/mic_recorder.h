#pragma once

#import <AVFoundation/AVFoundation.h>
#include "logger.h"

class MicRecorder {
public:
    MicRecorder();
    ~MicRecorder();
    
    bool Start();
    void Stop();
    void SetVolume(float volume);
    
private:
    AVAudioEngine* audioEngine_;
    AVAudioInputNode* inputNode_;
    AVAudioSinkNode* sinkNode_;
    AVAudioMixerNode* mixerNode_;
    AVAudioFormat* audioFormat_;
    
    // WAV 文件输出相关
    ExtAudioFileRef audioFile_;
    AudioStreamBasicDescription fileFormat_;
    NSString* outputPath_;
    
    // 音频数据回调
    static OSStatus AudioDataCallback(
        void* inRefCon,
        AudioUnitRenderActionFlags* ioActionFlags,
        const AudioTimeStamp* inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList* ioData);
};
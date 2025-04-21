#pragma once

#import <AVFoundation/AVFoundation.h>
#include "logger.h"

class AVAudioEngineTest {
public:
    AVAudioEngineTest();
    ~AVAudioEngineTest();
    
    bool Start();
    void Stop();
    void SetVolume(float volume);
    
private:
    AVAudioEngine* audioEngine_;
    AVAudioInputNode* inputNode_;
    AVAudioOutputNode* outputNode_;
    AVAudioMixerNode* mixerNode_;
    AVAudioFormat* audioFormat_;
};
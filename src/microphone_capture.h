#pragma once

#include <memory>
#include <string>
#include <vector>
#include "ring_buffer.h"
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>

class MicrophoneCapture {
public:
    MicrophoneCapture();
    ~MicrophoneCapture();
    
    bool Start();
    void Stop();
    bool ReadAudioData(std::vector<float>& data, size_t count);
    
private:
    class Impl;
    std::unique_ptr<Impl> impl_;
    
    static OSStatus InputCallback(void* inRefCon,
                                AudioUnitRenderActionFlags* ioActionFlags,
                                const AudioTimeStamp* inTimeStamp,
                                UInt32 inBusNumber,
                                UInt32 inNumberFrames,
                                AudioBufferList* ioData);
}; 
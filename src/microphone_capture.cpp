#include "microphone_capture.h"
#include "logger.h"
#include <CoreServices/CoreServices.h>
#include <iostream>

class MicrophoneCapture::Impl {
public:
    Impl() : audioUnit_(nullptr), isRunning_(false), ringBuffer_(1024 * 1024) {
    }
    
    ~Impl() {
        Stop();
    }
    
    bool Start() {
        if (isRunning_) {
            return true;
        }
        
        // 创建音频单元
        AudioComponentDescription desc;
        desc.componentType = kAudioUnitType_Output;
        desc.componentSubType = kAudioUnitSubType_HALOutput;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;
        
        AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
        if (!comp) {
            std::cerr << "Failed to find audio component" << std::endl;
            return false;
        }
        
        OSStatus status = AudioComponentInstanceNew(comp, &audioUnit_);
        if (status != noErr) {
            std::cerr << "Failed to create audio unit instance: " << status << std::endl;
            return false;
        }
        
        // 获取默认输入设备
        AudioDeviceID inputDevice = kAudioDeviceUnknown;
        UInt32 size = sizeof(inputDevice);
        AudioObjectPropertyAddress propertyAddress = {
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        
        status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                          &propertyAddress,
                                          0,
                                          nullptr,
                                          &size,
                                          &inputDevice);
        if (status != noErr) {
            std::cerr << "Failed to get default input device: " << status << std::endl;
            return false;
        }
        
        // 获取设备名称
        CFStringRef deviceName = nullptr;
        size = sizeof(deviceName);
        propertyAddress.mSelector = kAudioObjectPropertyName;
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
        propertyAddress.mElement = kAudioObjectPropertyElementMain;
        
        status = AudioObjectGetPropertyData(inputDevice,
                                          &propertyAddress,
                                          0,
                                          nullptr,
                                          &size,
                                          &deviceName);
        if (status == noErr && deviceName) {
            char name[256];
            CFStringGetCString(deviceName, name, sizeof(name), kCFStringEncodingUTF8);
            std::cerr << "Using input device: " << name << std::endl;
            CFRelease(deviceName);
        }
        
        // 设置输入设备
        status = AudioUnitSetProperty(audioUnit_,
                                    kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global,
                                    0,
                                    &inputDevice,
                                    sizeof(inputDevice));
        if (status != noErr) {
            std::cerr << "Failed to set input device: " << status << std::endl;
            return false;
        }
        
        // 启用输入
        UInt32 enableIO = 1;
        status = AudioUnitSetProperty(audioUnit_,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    1,
                                    &enableIO,
                                    sizeof(enableIO));
        if (status != noErr) {
            std::cerr << "Failed to enable input: " << status << std::endl;
            return false;
        }
        
        // 获取当前设备的格式
        AudioStreamBasicDescription deviceFormat;
        size = sizeof(deviceFormat);
        status = AudioUnitGetProperty(audioUnit_,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    1,
                                    &deviceFormat,
                                    &size);
        if (status != noErr) {
            std::cerr << "Failed to get device format: " << status << std::endl;
            return false;
        }
        
        // 设置音频格式
        AudioStreamBasicDescription format = deviceFormat;
        format.mFormatID = kAudioFormatLinearPCM;
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        format.mBitsPerChannel = 32;
        format.mChannelsPerFrame = 1;
        format.mFramesPerPacket = 1;
        format.mBytesPerFrame = format.mBitsPerChannel / 8 * format.mChannelsPerFrame;
        format.mBytesPerPacket = format.mBytesPerFrame * format.mFramesPerPacket;
        
        // 设置格式
        status = AudioUnitSetProperty(audioUnit_,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    1,
                                    &format,
                                    sizeof(format));
        if (status != noErr) {
            std::cerr << "Failed to set audio format: " << status << std::endl;
            return false;
        }
        
        // 设置回调
        AURenderCallbackStruct callback;
        callback.inputProc = MicrophoneCapture::InputCallback;
        callback.inputProcRefCon = this;
        
        status = AudioUnitSetProperty(audioUnit_,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Global,
                                    0,
                                    &callback,
                                    sizeof(callback));
        if (status != noErr) {
            std::cerr << "Failed to set input callback: " << status << std::endl;
            return false;
        }
        
        // 初始化音频单元
        status = AudioUnitInitialize(audioUnit_);
        if (status != noErr) {
            std::cerr << "Failed to initialize audio unit: " << status << std::endl;
            return false;
        }
        
        // 开始录制
        status = AudioOutputUnitStart(audioUnit_);
        if (status != noErr) {
            std::cerr << "Failed to start audio unit: " << status << std::endl;
            return false;
        }
        
        isRunning_ = true;
        return true;
    }
    
    void Stop() {
        if (!isRunning_) {
            return;
        }
        
        if (audioUnit_) {
            AudioOutputUnitStop(audioUnit_);
            AudioUnitUninitialize(audioUnit_);
            AudioComponentInstanceDispose(audioUnit_);
            audioUnit_ = nullptr;
        }
        
        isRunning_ = false;
    }
    
    bool ReadAudioData(std::vector<float>& data, size_t count) {
        if (!isRunning_) {
            return false;
        }
        
        data.resize(count);
        return ringBuffer_.read(data.data(), count);
    }
    
    void HandleInput(AudioUnitRenderActionFlags* ioActionFlags,
                    const AudioTimeStamp* inTimeStamp,
                    UInt32 inBusNumber,
                    UInt32 inNumberFrames,
                    AudioBufferList* ioData) {
        if (!isRunning_) {
            return;
        }
        
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mNumberChannels = 1;
        bufferList.mBuffers[0].mDataByteSize = inNumberFrames * sizeof(float);
        bufferList.mBuffers[0].mData = new float[inNumberFrames];
        
        OSStatus status = AudioUnitRender(audioUnit_,
                                        ioActionFlags,
                                        inTimeStamp,
                                        inBusNumber,
                                        inNumberFrames,
                                        &bufferList);
        
        if (status == noErr) {
            ringBuffer_.write(static_cast<float*>(bufferList.mBuffers[0].mData), inNumberFrames);
        }
        
        delete[] static_cast<float*>(bufferList.mBuffers[0].mData);
    }
    
private:
    AudioUnit audioUnit_;
    bool isRunning_;
    RingBuffer ringBuffer_;
};

MicrophoneCapture::MicrophoneCapture() : impl_(std::make_unique<Impl>()) {
}

MicrophoneCapture::~MicrophoneCapture() {
}

bool MicrophoneCapture::Start() {
    return impl_->Start();
}

void MicrophoneCapture::Stop() {
    impl_->Stop();
}

bool MicrophoneCapture::ReadAudioData(std::vector<float>& data, size_t count) {
    return impl_->ReadAudioData(data, count);
}

OSStatus MicrophoneCapture::InputCallback(void* inRefCon,
                                        AudioUnitRenderActionFlags* ioActionFlags,
                                        const AudioTimeStamp* inTimeStamp,
                                        UInt32 inBusNumber,
                                        UInt32 inNumberFrames,
                                        AudioBufferList* ioData) {
    auto impl = static_cast<Impl*>(inRefCon);
    impl->HandleInput(ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);
    return noErr;
} 
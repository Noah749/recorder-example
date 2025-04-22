#include "audio_system_capture.h"
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>

constexpr AudioObjectPropertyAddress PropertyAddress(AudioObjectPropertySelector selector,
                                                     AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
                                                     AudioObjectPropertyElement element = kAudioObjectPropertyElementMain) noexcept {
    return {selector, scope, element};
}

enum class StreamDirection : UInt32 {
    output,
    input
};

AudioSystemCapture::AudioSystemCapture() 
    : deviceID_(kAudioObjectUnknown)
    , inputStreamList_(std::make_shared<std::vector<AudioStreamBasicDescription>>())
    , outputStreamList_(std::make_shared<std::vector<AudioStreamBasicDescription>>())
    , recordingEnabled_(false)
    , loopbackEnabled_(false)
    , recordingURL_(nullptr)
    , fileList_(std::make_shared<std::vector<ExtAudioFileRef>>())
    , ioProcID_(nullptr) {
}

AudioSystemCapture::~AudioSystemCapture() {
    StopIO();
    UnregisterListeners();
}

void AudioSystemCapture::SetDeviceID(AudioObjectID deviceID) {
    if (deviceID_ == deviceID) {
        return;
    }
    AdaptToDevice(deviceID);
}

bool AudioSystemCapture::StartRecording() {
    if (recordingEnabled_) {
        return true;
    }
    
    recordingEnabled_ = true;
    if (loopbackEnabled_) {
        StopIO();
    }
    
    if (!MakeRecordingFiles()) {
        recordingEnabled_ = false;
        return false;
    }
    
    if (!StartIO()) {
        recordingEnabled_ = false;
        CleanUpRecordingFiles();
        return false;
    }
    
    return true;
}

void AudioSystemCapture::StopRecording() {
    if (!recordingEnabled_) {
        return;
    }
    
    recordingEnabled_ = false;
    if (loopbackEnabled_) {
        CleanUpRecordingFiles();
    } else {
        StopIO();
    }
}

bool AudioSystemCapture::StartLoopback() {
    if (loopbackEnabled_) {
        return true;
    }
    
    loopbackEnabled_ = true;
    if (recordingEnabled_) {
        return true;
    }
    
    if (!StartIO()) {
        loopbackEnabled_ = false;
        return false;
    }
    
    return true;
}

void AudioSystemCapture::StopLoopback() {
    if (!loopbackEnabled_) {
        return;
    }
    
    loopbackEnabled_ = false;
    StopIO();
}

bool AudioSystemCapture::AdaptToDevice(AudioObjectID deviceID) {
    StopIO();
    UnregisterListeners();
    
    deviceID_ = deviceID;
    CatalogDeviceStreams();
    RegisterListeners();
    
    bool success = true;
    if (success && (deviceID_ != kAudioObjectUnknown)) {
        if (recordingEnabled_) {
            success = StartRecording();
        } else if (loopbackEnabled_) {
            success = StartIO();
        }
    }
    return success;
}

void AudioSystemCapture::CatalogDeviceStreams() {
    inputStreamList_->clear();
    outputStreamList_->clear();
    
    if (deviceID_ == kAudioObjectUnknown) {
        return;
    }
    
    // 获取设备流列表
    UInt32 size = 0;
    AudioObjectPropertyAddress address = PropertyAddress(kAudioDevicePropertyStreams);
    OSStatus error = AudioObjectGetPropertyDataSize(deviceID_, &address, 0, nullptr, &size);
    auto streamCount = size / sizeof(AudioObjectID);
    if (error != kAudioHardwareNoError || streamCount == 0) {
        return;
    }
    
    std::vector<AudioObjectID> streamList(streamCount);
    error = AudioObjectGetPropertyData(deviceID_, &address, 0, nullptr, &size, streamList.data());
    if (error != kAudioHardwareNoError) {
        return;
    }
    
    streamList.resize(size / sizeof(AudioObjectID));
    for (auto streamID : streamList) {
        // 获取每个流的格式
        address = PropertyAddress(kAudioStreamPropertyVirtualFormat);
        AudioStreamBasicDescription format;
        size = sizeof(AudioStreamBasicDescription);
        memset(&format, 0, size);
        error = AudioObjectGetPropertyData(streamID, &address, 0, nullptr, &size, &format);
        if (error == kAudioHardwareNoError) {
            address = PropertyAddress(kAudioStreamPropertyDirection);
            StreamDirection direction = StreamDirection::output;
            size = sizeof(UInt32);
            AudioObjectGetPropertyData(streamID, &address, 0, nullptr, &size, &direction);
            if (direction == StreamDirection::output) {
                outputStreamList_->push_back(format);
            } else {
                inputStreamList_->push_back(format);
            }
        }
    }
}

bool AudioSystemCapture::StartIO() {
    Logger::info("开始IO");
    AudioDeviceIOProcID ioProcID = nullptr;
    auto error = AudioDeviceCreateIOProcID(deviceID_, IOProc, this, &ioProcID);
    if (error != kAudioHardwareNoError) {
        return false;
    }
    ioProcID_ = ioProcID;
    
    error = AudioDeviceStart(deviceID_, ioProcID_);
    if (error != kAudioHardwareNoError) {
        AudioDeviceDestroyIOProcID(deviceID_, ioProcID_);
        ioProcID_ = nullptr;
        return false;
    }
    return true;
}

void AudioSystemCapture::StopIO() {
    Logger::info("停止IO");
    if (ioProcID_) {
        AudioDeviceStop(deviceID_, ioProcID_);
        AudioDeviceDestroyIOProcID(deviceID_, ioProcID_);
        ioProcID_ = nullptr;
    }
    CleanUpRecordingFiles();
}

void AudioSystemCapture::RegisterListeners() {
    if (deviceID_ != 0) {
        auto address = PropertyAddress(kAudioDevicePropertyDeviceIsAlive);
        AudioObjectAddPropertyListener(deviceID_, &address, DeviceChangedListener, this);
        address = PropertyAddress(kAudioAggregateDevicePropertyFullSubDeviceList);
        AudioObjectAddPropertyListener(deviceID_, &address, DeviceChangedListener, this);
        address = PropertyAddress(kAudioAggregateDevicePropertyTapList);
        AudioObjectAddPropertyListener(deviceID_, &address, DeviceChangedListener, this);
    }
}

void AudioSystemCapture::UnregisterListeners() {
    if (deviceID_ != 0) {
        auto address = PropertyAddress(kAudioDevicePropertyDeviceIsAlive);
        AudioObjectRemovePropertyListener(deviceID_, &address, DeviceChangedListener, this);
        address = PropertyAddress(kAudioAggregateDevicePropertyFullSubDeviceList);
        AudioObjectRemovePropertyListener(deviceID_, &address, DeviceChangedListener, this);
        address = PropertyAddress(kAudioAggregateDevicePropertyTapList);
        AudioObjectRemovePropertyListener(deviceID_, &address, DeviceChangedListener, this);
    }
}

bool AudioSystemCapture::MakeRecordingFiles() {
    // 如果没有输入流，返回false
    if (inputStreamList_->size() == 0) {
        Logger::error("没有可用的输入流");
        return false;
    }
    
    // 获取当前工作目录
    char* currentDir = getcwd(nullptr, 0);
    if (!currentDir) {
        Logger::error("无法获取当前工作目录");
        return false;
    }
    
    auto streamFormats = inputStreamList_;
    auto files = fileList_;
    for (unsigned index = 0; index < streamFormats->size(); ++index) {
        auto format = streamFormats->at(index);
        Logger::info("创建录制文件，格式: %u Hz, %u 通道, %u 位", 
                    (unsigned int)format.mSampleRate,
                    (unsigned int)format.mChannelsPerFrame,
                    (unsigned int)format.mBitsPerChannel);
        
        auto* path = [NSString stringWithFormat: @"%s/recording.caf", currentDir];
        auto* url = [NSURL fileURLWithPath: path];
        recordingURL_ = url;
        
        // 设置客户端格式
        AudioStreamBasicDescription clientFormat = format;
        clientFormat.mFormatID = kAudioFormatLinearPCM;
        clientFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        clientFormat.mBitsPerChannel = 32;
        clientFormat.mBytesPerFrame = clientFormat.mBitsPerChannel / 8 * clientFormat.mChannelsPerFrame;
        clientFormat.mFramesPerPacket = 1;
        clientFormat.mBytesPerPacket = clientFormat.mBytesPerFrame * clientFormat.mFramesPerPacket;
        
        ExtAudioFileRef file = nullptr;
        OSStatus error = ExtAudioFileCreateWithURL((__bridge CFURLRef)url, 
                                                 kAudioFileCAFType, 
                                                 &format, 
                                                 nullptr, 
                                                 kAudioFileFlags_EraseFile, 
                                                 &file);
        if (error != noErr) {
            Logger::error("创建音频文件失败: %d", (int)error);
            free(currentDir);
            CleanUpRecordingFiles();
            return false;
        }
        
        // 设置客户端格式
        error = ExtAudioFileSetProperty(file,
                                      kExtAudioFileProperty_ClientDataFormat,
                                      sizeof(clientFormat),
                                      &clientFormat);
        if (error != noErr) {
            Logger::error("设置客户端格式失败: %d", (int)error);
            ExtAudioFileDispose(file);
            free(currentDir);
            CleanUpRecordingFiles();
            return false;
        }
        
        files->push_back(file);
    }
    
    free(currentDir);
    return true;
}

void AudioSystemCapture::CleanUpRecordingFiles() {
    auto list = fileList_;
    for (auto file : *list) {
        ExtAudioFileDispose(file);
    }
    list->clear();
}

OSStatus AudioSystemCapture::DeviceChangedListener(
    AudioObjectID inObjectID,
    UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress* inAddresses,
    void* inClientData) {
    auto* capture = static_cast<AudioSystemCapture*>(inClientData);
    if (capture != nullptr) {
        for (unsigned index = 0; index < inNumberAddresses; ++index) {
            auto address = inAddresses[index];
            switch (address.mSelector) {
                case kAudioDevicePropertyDeviceIsAlive:
                    capture->AdaptToDevice(kAudioObjectUnknown);
                    break;
                case kAudioAggregateDevicePropertyFullSubDeviceList:
                case kAudioAggregateDevicePropertyTapList:
                    capture->AdaptToDevice(capture->deviceID_);
                    break;
            }
        }
    }
    return kAudioHardwareNoError;
}

OSStatus AudioSystemCapture::IOProc(
    AudioObjectID inDevice,
    const AudioTimeStamp* inNow,
    const AudioBufferList* inInputData,
    const AudioTimeStamp* inInputTime,
    AudioBufferList* outOutputData,
    const AudioTimeStamp* inOutputTime,
    void* inClientData) {
    auto* capture = static_cast<AudioSystemCapture*>(inClientData);
    auto fileList = capture->fileList_;
    
    UInt32 numberInputBuffers = 0;
    UInt32 numberFramesToRecord = 0;
    if (inInputData != nullptr && inInputData->mNumberBuffers > 0) {
        numberInputBuffers = inInputData->mNumberBuffers;
        numberFramesToRecord = inInputData->mBuffers[0].mDataByteSize / (inInputData->mBuffers[0].mNumberChannels * sizeof(Float32));
        Logger::debug("收到音频数据: %u 个缓冲区, %u 帧", numberInputBuffers, numberFramesToRecord);
    } else {
        Logger::debug("没有收到音频数据");
        return kAudioHardwareNoError;
    }
    
    for (size_t index = 0; index < numberInputBuffers; ++index) {
        AudioBuffer buffer = inInputData->mBuffers[index];
        if (capture->recordingEnabled_ && index < fileList->size()) {
            // 将输入缓冲区数据写入录制文件
            AudioBufferList writeData;
            writeData.mNumberBuffers = 1;
            writeData.mBuffers[0] = buffer;
            
            // 检查音频数据是否有效
            if (buffer.mData == nullptr || buffer.mDataByteSize == 0) {
                Logger::error("无效的音频数据: 缓冲区 %zu", index);
                continue;
            }
            
            // 写入音频数据
            OSStatus error = ExtAudioFileWriteAsync(fileList->at(index), numberFramesToRecord, &writeData);
            if (error != noErr) {
                Logger::error("写入音频数据失败: %d", (int)error);
            }
        }
    }
    
    return kAudioHardwareNoError;
} 
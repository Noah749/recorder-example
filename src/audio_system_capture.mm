#include "audio_system_capture.h"
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>
#include <vector>
#include <mutex>
#include <condition_variable>
#include "audio_device_manager.h"
#include "logger.h"
#include "ring_buffer.h"
constexpr AudioObjectPropertyAddress PropertyAddress(AudioObjectPropertySelector selector,
                                                     AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
                                                     AudioObjectPropertyElement element = kAudioObjectPropertyElementMain) noexcept {
    return {selector, scope, element};
}

enum class StreamDirection : UInt32 {
    output,
    input
};

class AudioSystemCapture::Impl {
public:
    Impl() : ring_buffer_(44100 * 2) {}
    
    RingBuffer ring_buffer_;
};

AudioSystemCapture::AudioSystemCapture(AggregateDevice* aggregateDevice) 
    : deviceID_(kAudioObjectUnknown)
    , inputStreamList_(std::make_shared<std::vector<AudioStreamBasicDescription>>())
    , outputStreamList_(std::make_shared<std::vector<AudioStreamBasicDescription>>())
    , recordingEnabled_(false)
    , loopbackEnabled_(false)
    , ioProcID_(nullptr)
    , impl_(std::make_unique<Impl>())
    , aggregateDevice_(aggregateDevice) {
    if (aggregateDevice_) {
        SetDeviceID(aggregateDevice_->deviceID);
    }
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

void AudioSystemCapture::SetAudioDataCallback(std::function<void(const AudioBufferList*, UInt32, Float64)> callback) {
    audioDataCallback_ = std::move(callback);
}

bool AudioSystemCapture::StartRecording() {
    if (recordingEnabled_) {
        return true;
    }
    
    recordingEnabled_ = true;
    if (loopbackEnabled_) {
        StopIO();
    }
    
    if (!StartIO()) {
        recordingEnabled_ = false;
        return false;
    }
    
    return true;
}

void AudioSystemCapture::StopRecording() {
    if (!recordingEnabled_) {
        return;
    }
    
    recordingEnabled_ = false;
    if (!loopbackEnabled_) {
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
//    CatalogDeviceStreams();
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
        Logger::error("设备 ID 无效");
        return;
    }
    
    // 获取设备流列表
    UInt32 size = 0;
    AudioObjectPropertyAddress address = PropertyAddress(kAudioDevicePropertyStreams);
    OSStatus error = AudioObjectGetPropertyDataSize(deviceID_, &address, 0, nullptr, &size);
    auto streamCount = size / sizeof(AudioObjectID);
    if (error != kAudioHardwareNoError || streamCount == 0) {
        Logger::error("CatalogDeviceStreams 获取设备流列表失败: %d, 流数量: %zu", (int)error, streamCount);
        return;
    }
    
    std::vector<AudioObjectID> streamList(streamCount);
    error = AudioObjectGetPropertyData(deviceID_, &address, 0, nullptr, &size, streamList.data());
    if (error != kAudioHardwareNoError) {
        Logger::error("获取设备流数据失败: %d", (int)error);
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
        } else {
            Logger::error("获取流 %u 的格式失败: %d", (unsigned int)streamID, (int)error);
        }
    }
}

bool AudioSystemCapture::StartIO() {
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
    static bool isStopping = false;
    if (isStopping) {
        return;
    }
    isStopping = true;
    
    if (ioProcID_) {
        AudioDeviceStop(deviceID_, ioProcID_);
        AudioDeviceDestroyIOProcID(deviceID_, ioProcID_);
        ioProcID_ = nullptr;
    }
    
    isStopping = false;
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
    
    if (inInputData != nullptr && inInputData->mNumberBuffers > 0) {
        const AudioBuffer& inputBuffer = inInputData->mBuffers[0];
        
        // 检查输入数据是否有效
        if (inputBuffer.mData == nullptr || inputBuffer.mDataByteSize == 0) {
            return kAudioHardwareNoError;
        }
        
        // 计算帧数
        UInt32 bytesPerFrame = inputBuffer.mNumberChannels * sizeof(Float32);
        UInt32 numberFrames = inputBuffer.mDataByteSize / bytesPerFrame;
        
        if (numberFrames == 0) {
            return kAudioHardwareNoError;
        }
        
        // 将音频数据写入环形缓冲区
        float* audioData = static_cast<float*>(inputBuffer.mData);
        size_t sampleCount = numberFrames * inputBuffer.mNumberChannels;
        
        // 如果设置了回调函数，则调用
        if (capture->audioDataCallback_) {
            // 使用输入时间戳
            double timestamp = inInputTime->mSampleTime / capture->format_.mSampleRate;
            capture->audioDataCallback_(inInputData, numberFrames, timestamp);
        }
    }
    
    return kAudioHardwareNoError;
}

// 添加新方法用于从环形缓冲区读取数据
bool AudioSystemCapture::ReadAudioData(float* buffer, size_t count) {
    return impl_->ring_buffer_.read(buffer, count);
}

void AudioSystemCapture::ClearRingBuffer() {
    impl_->ring_buffer_.clear();
}

bool AudioSystemCapture::GetAudioFormat(AudioStreamBasicDescription& format) {
    if (deviceID_ == kAudioObjectUnknown) {
        return false;
    }
    
    CatalogDeviceStreams();
    if (inputStreamList_->empty()) {
        return false;
    }
    
    format = inputStreamList_->front();
    format_ = format;  // 保存格式信息
    return true;
}

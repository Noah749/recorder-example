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

constexpr AudioObjectPropertyAddress PropertyAddress(AudioObjectPropertySelector selector,
                                                     AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
                                                     AudioObjectPropertyElement element = kAudioObjectPropertyElementMain) noexcept {
    return {selector, scope, element};
}

enum class StreamDirection : UInt32 {
    output,
    input
};

class RingBuffer {
public:
    RingBuffer(size_t size) 
        : buffer_(size)
        , read_pos_(0)
        , write_pos_(0)
        , size_(size)
        , overflow_count_(0)
        , underflow_count_(0)
        , max_used_size_(0) {
    }
    
    bool write(const float* data, size_t count) {
        std::unique_lock<std::mutex> lock(mutex_);
        
        if (available_write() < count) {
            // 如果缓冲区使用率超过 80%，进行扩容
            if (available_read() > size_ * 0.8) {
                size_t new_size = size_ * 2;
                std::vector<float> new_buffer(new_size);
                
                // 复制现有数据到新缓冲区
                size_t read_size = available_read();
                for (size_t i = 0; i < read_size; ++i) {
                    new_buffer[i] = buffer_[(read_pos_ + i) % size_];
                }
                
                buffer_ = std::move(new_buffer);
                size_ = new_size;
                read_pos_ = 0;
                write_pos_ = read_size;
                
                Logger::info("环形缓冲区扩容: %zu -> %zu", size_ / 2, size_);
            } else {
                // 缓冲区溢出，记录并返回 false
                overflow_count_++;
                if (overflow_count_ % 100 == 0) { // 每溢出100次记录一次警告
                    Logger::error("环形缓冲区溢出次数: %zu", overflow_count_);
                }
                return false;
            }
        }
        
        // 写入数据
        for (size_t i = 0; i < count; ++i) {
            buffer_[write_pos_] = data[i];
            write_pos_ = (write_pos_ + 1) % size_;
        }
        
        // 更新最大使用量
        size_t used_size = available_read();
        if (used_size > max_used_size_) {
            max_used_size_ = used_size;
        }
        
        cv_.notify_one();
        return true;
    }
    
    bool read(float* data, size_t count) {
        std::unique_lock<std::mutex> lock(mutex_);
        
        if (available_read() < count) {
            underflow_count_++;
            if (underflow_count_ % 100 == 0) { // 每欠载100次记录一次警告
                Logger::error("环形缓冲区欠载次数: %zu", underflow_count_);
            }
            return false;
        }
        
        for (size_t i = 0; i < count; ++i) {
            data[i] = buffer_[read_pos_];
            read_pos_ = (read_pos_ + 1) % size_;
        }
        return true;
    }
    
    size_t available_read() const {
        if (write_pos_ >= read_pos_) {
            return write_pos_ - read_pos_;
        }
        return size_ - read_pos_ + write_pos_;
    }
    
    size_t available_write() const {
        return size_ - available_read() - 1;
    }
    
    // 获取统计信息
    struct Stats {
        size_t overflow_count;
        size_t underflow_count;
        size_t max_used_size;
        size_t current_size;
    };
    
    Stats get_stats() const {
        std::unique_lock<std::mutex> lock(mutex_);
        return {
            overflow_count_,
            underflow_count_,
            max_used_size_,
            size_
        };
    }
    
private:
    std::vector<float> buffer_;
    size_t read_pos_;
    size_t write_pos_;
    size_t size_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    
    // 统计信息
    size_t overflow_count_;    // 溢出次数
    size_t underflow_count_;   // 欠载次数
    size_t max_used_size_;     // 最大使用量
};

class AudioSystemCapture::Impl {
public:
    Impl() : ring_buffer_(44100 * 2) {} // 1秒的缓冲区
    
    RingBuffer ring_buffer_;
    AudioDeviceManager device_manager_;
};

AudioSystemCapture::AudioSystemCapture() 
    : deviceID_(kAudioObjectUnknown)
    , inputStreamList_(std::make_shared<std::vector<AudioStreamBasicDescription>>())
    , outputStreamList_(std::make_shared<std::vector<AudioStreamBasicDescription>>())
    , recordingEnabled_(false)
    , loopbackEnabled_(false)
    , ioProcID_(nullptr)
    , impl_(std::make_unique<Impl>()) {
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

void AudioSystemCapture::SetAudioDataCallback(std::function<void(const AudioBufferList*, UInt32)> callback) {
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
        UInt32 numberFramesToRecord = inInputData->mBuffers[0].mDataByteSize / (inInputData->mBuffers[0].mNumberChannels * sizeof(Float32));
        
        // 将音频数据写入环形缓冲区
        float* audioData = static_cast<float*>(inInputData->mBuffers[0].mData);
        capture->impl_->ring_buffer_.write(audioData, numberFramesToRecord * inInputData->mBuffers[0].mNumberChannels);
        
        // 如果设置了回调函数，则调用
        if (capture->audioDataCallback_) {
            capture->audioDataCallback_(inInputData, numberFramesToRecord);
        }
    }
    
    return kAudioHardwareNoError;
}

// 添加新方法用于从环形缓冲区读取数据
bool AudioSystemCapture::ReadAudioData(float* buffer, size_t count) {
    return impl_->ring_buffer_.read(buffer, count);
}

bool AudioSystemCapture::CreateTapDevice() {
    // 查找并删除指定名称的设备
    auto devicesToRemove = impl_->device_manager_.GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
    Logger::info("找到 %zu 个需要删除的聚合设备", devicesToRemove.size());
    
    for (const auto& deviceID : devicesToRemove) {
        auto taps = impl_->device_manager_.GetDeviceTaps(deviceID);
        Logger::info("设备 %u 有 %zu 个 tap", (unsigned int)deviceID, taps.size());
        for (const auto& tap : taps) {
            Logger::info("正在删除 tap %u", (unsigned int)tap);
            impl_->device_manager_.RemoveTap(tap);
        }
        Logger::info("正在删除设备 %u", (unsigned int)deviceID);
        impl_->device_manager_.RemoveAggregateDevice(deviceID);
    }
    
    // 验证设备是否已删除
    auto remainingDevices = impl_->device_manager_.GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
    Logger::info("删除后剩余 %zu 个聚合设备", remainingDevices.size());
    
    // 创建新的聚合设备
    AudioObjectID newDeviceID = impl_->device_manager_.CreateAggregateDevice("plaud.ai Aggregate Audio Device");
    if (newDeviceID == kAudioObjectUnknown) {
        Logger::error("创建聚合设备失败");
        return false;
    }
    Logger::info("成功创建聚合设备，ID: %u", (unsigned int)newDeviceID);
    
    // 创建 tap
    AudioObjectID tapID = impl_->device_manager_.CreateTap(@"plaud.ai tap");
    if (tapID == kAudioObjectUnknown) {
        Logger::error("创建 tap 失败");
        return false;
    }
    Logger::info("成功创建 tap，ID: %u", (unsigned int)tapID);
    
    // 添加 tap 到设备
    if (!impl_->device_manager_.AddTapToDevice(tapID, newDeviceID)) {
        Logger::error("添加 tap 到设备失败");
        return false;
    }
    Logger::info("成功将 tap 添加到设备");
    
    // 设置设备ID
    SetDeviceID(newDeviceID);
    return true;
} 
#pragma once

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include "logger.h"
#include <vector>
#include <memory>
#include <functional>

class AudioSystemCapture {
public:
    AudioSystemCapture();
    ~AudioSystemCapture();
    
    // 设置设备ID
    void SetDeviceID(AudioObjectID deviceID);
    
    // 开始录制
    bool StartRecording();
    
    // 停止录制
    void StopRecording();
    
    // 开始循环播放
    bool StartLoopback();
    
    // 停止循环播放
    void StopLoopback();
    
    // 设置音频数据回调
    void SetAudioDataCallback(std::function<void(const AudioBufferList*, UInt32)> callback);
    
    bool CreateTapDevice();
    bool ReadAudioData(float* buffer, size_t count);
    
    // 获取设备 ID
    AudioObjectID GetDeviceID() const { return deviceID_; }
    
    // 清理环形缓冲区
    void ClearRingBuffer();
    
    // 获取音频格式
    bool GetAudioFormat(AudioStreamBasicDescription& format) {
        if (deviceID_ == kAudioObjectUnknown) {
            return false;
        }
        
        CatalogDeviceStreams();
        if (inputStreamList_->empty()) {
            return false;
        }
        
        format = inputStreamList_->front();
        return true;
    }
    
private:
    class Impl;
    std::unique_ptr<Impl> impl_;
    
    // 设备属性监听回调
    static OSStatus DeviceChangedListener(
        AudioObjectID inObjectID,
        UInt32 inNumberAddresses,
        const AudioObjectPropertyAddress* inAddresses,
        void* inClientData);
    
    // IO处理回调
    static OSStatus IOProc(
        AudioObjectID inDevice,
        const AudioTimeStamp* inNow,
        const AudioBufferList* inInputData,
        const AudioTimeStamp* inInputTime,
        AudioBufferList* outOutputData,
        const AudioTimeStamp* inOutputTime,
        void* inClientData);
    
    // 适配设备
    bool AdaptToDevice(AudioObjectID deviceID);
    
    // 注册监听器
    void RegisterListeners();
    
    // 注销监听器
    void UnregisterListeners();
    
    // 开始IO
    bool StartIO();
    
    // 停止IO
    void StopIO();
    
    // 获取设备流信息
    void CatalogDeviceStreams();
    
private:
    AudioObjectID deviceID_;
    std::shared_ptr<std::vector<AudioStreamBasicDescription>> inputStreamList_;
    std::shared_ptr<std::vector<AudioStreamBasicDescription>> outputStreamList_;
    bool recordingEnabled_;
    bool loopbackEnabled_;
    AudioDeviceIOProcID ioProcID_;
    std::function<void(const AudioBufferList*, UInt32)> audioDataCallback_;
}; 
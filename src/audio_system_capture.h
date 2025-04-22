#pragma once

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include "logger.h"
#include <vector>
#include <memory>

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
    
    // 获取录制文件URL
    NSURL* GetRecordingURL() const { return recordingURL_; }
    
private:
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
    
    // 创建录制文件
    bool MakeRecordingFiles();
    
    // 清理录制文件
    void CleanUpRecordingFiles();
    
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
    NSURL* recordingURL_;
    std::shared_ptr<std::vector<ExtAudioFileRef>> fileList_;
    AudioDeviceIOProcID ioProcID_;
}; 
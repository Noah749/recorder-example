#ifndef AUDIO_DEVICE_MANAGER_H
#define AUDIO_DEVICE_MANAGER_H

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include <string>

class AudioDeviceManager {
public:
    // 获取所有聚合设备
    std::vector<AudioObjectID> GetAggregateDevices();
    
    // 获取指定名称的聚合设备
    std::vector<AudioObjectID> GetAggregateDevicesByName(const std::string& deviceName);
    
    // 创建聚合设备
    AudioObjectID CreateAggregateDevice(const char* deviceName);
    
    // 删除聚合设备
    bool RemoveAggregateDevice(AudioObjectID deviceID);
    
    // 创建 tap
    AudioObjectID CreateTap(const char* name);
    
    // 删除 tap
    bool RemoveTap(AudioObjectID tapID);
    
    // 添加 tap 到聚合设备
    bool AddTapToDevice(AudioObjectID tapID, AudioObjectID deviceID);
    
    // 从聚合设备移除 tap
    bool RemoveTapFromDevice(AudioObjectID tapID, AudioObjectID deviceID);
    
    // 获取设备的所有 tap
    std::vector<AudioObjectID> GetDeviceTaps(AudioObjectID deviceID);
};

#endif // AUDIO_DEVICE_MANAGER_H 
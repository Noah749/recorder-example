#ifndef AGGREGATE_DEVICE_H
#define AGGREGATE_DEVICE_H

#include <CoreAudio/CoreAudio.h>
#include <string>
#include <vector>

struct Tap {
    AudioObjectID tapID;
    std::string name;
};

class AggregateDevice {
public:
    AudioObjectID deviceID;
    std::string deviceName;
    std::vector<Tap> taps;

    AggregateDevice(const std::string& deviceName);
    ~AggregateDevice();

    // 获取设备的所有 tap
    std::vector<Tap> GetTaps() const;

    // 添加 tap 到设备
    bool AddTap(AudioObjectID tapID);

    // 从设备移除 tap
    bool RemoveTap(AudioObjectID tapID);

    // 创建 tap
    AudioObjectID CreateTap(const std::string& tapName);

    // 释放 tap
    bool ReleaseTap(AudioObjectID tapID);

private:
    void InitializeTaps();  // 声明初始化 taps 的方法
    void ReleaseTaps();  // 声明释放 taps 的方法
    std::string GetTapName(AudioObjectID tapID);  // 声明获取 tap 名称的方法
    // bool ReleaseTap(AudioObjectID tapID);  // 声明释放单个 tap 的方法
};

#endif // AGGREGATE_DEVICE_H 
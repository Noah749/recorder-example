#include "av_engine_test.h"
#include "logger.h"
#include "audio_device_manager.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>

void TestCoreAudioTaps() {
    @autoreleasepool {
        Logger::info("开始测试 core audio taps");

        AudioDeviceManager manager;
        
        // 获取所有聚合设备
        auto aggregateDevices = manager.GetAggregateDevices();
        Logger::info("找到 %zu 个聚合设备", aggregateDevices.size());
        
        // 打印每个设备的 tap
        for (const auto& deviceID : aggregateDevices) {
            Logger::info("\n检查设备 ID: %u", (unsigned int)deviceID);
            manager.GetDeviceTaps(deviceID);
        }

        // 查找并删除指定名称的设备
        auto devicesToRemove = manager.GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
        Logger::info("找到 %zu 个需要删除的聚合设备", devicesToRemove.size());

        for (const auto& deviceID : devicesToRemove) {
            auto taps = manager.GetDeviceTaps(deviceID);
            for (const auto& tap : taps) {
              manager.RemoveTap(tap);
            }
            manager.RemoveAggregateDevice(deviceID);
        }

        // 验证设备是否已删除
        auto remainingDevices = manager.GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
        Logger::info("删除后剩余 %zu 个聚合设备", remainingDevices.size());
        
        // 创建新的聚合设备
        AudioObjectID deviceID = manager.CreateAggregateDevice("plaud.ai Aggregate Audio Device");
        if (deviceID == kAudioObjectUnknown) {
            Logger::error("创建聚合设备失败");
            return;
        }
        
        // 创建 tap
        AudioObjectID tapID = manager.CreateTap(@"plaud.ai tap");
        if (tapID == kAudioObjectUnknown) {
            Logger::error("创建 tap 失败");
            return;
        }
        
        // 添加 tap 到设备
        if (!manager.AddTapToDevice(tapID, deviceID)) {
            Logger::error("添加 tap 到设备失败");
            return;
        }

        Logger::info("测试完成");
    }
} 
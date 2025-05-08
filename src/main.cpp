#include <iostream>
#include <string>
#include <filesystem>
#include <chrono>
#include <thread>
#include <sstream>
#include <iomanip>
#include "recorder.h"
#include "logger.h"
#include "mic_recorder.h"
#include <CoreAudio/CoreAudio.h>
#include "aggregate_device.h"

// 声明测试函数
void TestMicRecorder();
void TestSystemCaptureRecorder();
void TestAudioEngine();
void TestVoiceProcessingInput();
void TestAggregateDevice();  // 新增聚合设备测试函数

int main(int argc, char* argv[]) {
    try {
        // 初始化日志系统
        Logger::init("./logs");  // 指定日志目录
        Logger::setLevel(Logger::Level::DEBUG);
        Logger::info("启动本地录音程序");
        
        // 运行麦克风录音测试
        // TestMicRecorder();
        // 运行系统音频捕获测试
        // TestSystemCaptureRecorder();
        // 运行音频引擎 测试
        TestAudioEngine();

        // TestVoiceProcessingInput();
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "发生错误: " << e.what() << std::endl;
        return 1;
    }
}

// 聚合设备测试函数
void TestAggregateDevice() {
    Logger::info("开始测试聚合设备");
    
    // 创建聚合设备
    AggregateDevice device("Plaud.ai.AggregateDevice");
    AudioObjectID deviceID = device.deviceID;
    
    if (deviceID == kAudioObjectUnknown) {
        Logger::error("创建聚合设备失败");
        return;
    }
    
    Logger::info("聚合设备创建成功，ID: %u", (unsigned int)deviceID);
    
    // 获取设备名称
    std::string name = device.deviceName;
    Logger::info("设备名称: %s", name.c_str());
    
    // 获取设备的所有 tap
    std::vector<Tap> taps = device.GetTaps();
    Logger::info("设备 tap 数量: %zu", taps.size());
    for (const auto& tap : taps) {
        Logger::info("tap ID: %u, name: %s", tap.tapID, tap.name.c_str());
    }

    AudioObjectID tapID = device.CreateTap("Plaud.ai.Tap");
    bool added = device.AddTap(tapID);
    Logger::info("添加 tap 成功 %u", added);

    taps = device.GetTaps();
    Logger::info("设备 tap 数量: %zu", taps.size());
    for (const auto& tap : taps) {
        Logger::info("tap ID: %u, name: %s", tap.tapID, tap.name.c_str());
    }

    std::this_thread::sleep_for(std::chrono::seconds(10));
    bool removed = device.ReleaseTap(tapID);
    Logger::info("移除 tap 成功 %u", removed);

    taps = device.GetTaps();
    Logger::info("设备 tap 数量: %zu", taps.size());
    for (const auto& tap : taps) {
        Logger::info("tap ID: %u, name: %s", tap.tapID, tap.name.c_str());
    }
    
    Logger::info("聚合设备测试完成");
} 
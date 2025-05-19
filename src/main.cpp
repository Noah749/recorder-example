#include <iostream>
#include <string>
#include <filesystem>
#include <chrono>
#include <thread>
#include <sstream>
#include <iomanip>
#include "recorder.h"
#include "logger.h"
#include <CoreAudio/CoreAudio.h>
#include "aggregate_device.h"
#include "audio_system_capture.h"

void TestAudioEngine();
void TestAggregateDevice();  // 新增聚合设备测试函数

// 音频数据回调函数
void OnAudioData(const AudioBufferList* bufferList, UInt32 numberFrames) {
    if (bufferList && bufferList->mNumberBuffers > 0) {
        const AudioBuffer& buffer = bufferList->mBuffers[0];
        float* audioData = static_cast<float*>(buffer.mData);
        size_t sampleCount = numberFrames * buffer.mNumberChannels;
        
        // 这里可以处理音频数据，例如：
        // 1. 计算音量
        float sum = 0.0f;
        for (size_t i = 0; i < sampleCount; ++i) {
            sum += std::abs(audioData[i]);
        }
        float average = sum / sampleCount;
        
        // 2. 记录日志
        Logger::debug("收到音频数据: 帧数=%u, 通道数=%u, 平均音量=%.4f", 
                     numberFrames, buffer.mNumberChannels, average);
    }
}

int main(int argc, char* argv[]) {
    try {
        // 初始化日志系统
        Logger::init("./logs");  // 指定日志目录
        Logger::setLevel(Logger::Level::DEBUG);
        Logger::info("启动本地录音程序");
        
        // 运行音频引擎 测试
        // TestAudioEngine();
        TestAggregateDevice();

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
    
    // 创建音频捕获对象
    AudioSystemCapture capture(&device);
    
    // 设置音频数据回调
    capture.SetAudioDataCallback(OnAudioData);
    
    // 检查设备状态
    UInt32 isAlive = 0;
    UInt32 propertySize = sizeof(isAlive);
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyDeviceIsAlive,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    OSStatus status = AudioObjectGetPropertyData(deviceID, &address, 0, nullptr, &propertySize, &isAlive);
    if (status != kAudioHardwareNoError || !isAlive) {
        Logger::error("设备不可用，状态码: %d", (int)status);
        return;
    }
    
    // 获取设备名称
    CFStringRef deviceName = nullptr;
    propertySize = sizeof(deviceName);
    address.mSelector = kAudioObjectPropertyName;
    status = AudioObjectGetPropertyData(deviceID, &address, 0, nullptr, &propertySize, &deviceName);
    if (status == kAudioHardwareNoError && deviceName) {
        char name[256];
        CFStringGetCString(deviceName, name, sizeof(name), kCFStringEncodingUTF8);
        Logger::info("设备名称: %s", name);
        CFRelease(deviceName);
    }
    
    // 开始录音
    if (!capture.StartRecording()) {
        Logger::error("启动录音失败");
        return;
    }
    
    Logger::info("开始录音，等待10秒...");
    
    // 等待10秒
    std::this_thread::sleep_for(std::chrono::seconds(10));
    
    // 停止录音
    capture.StopRecording();
    Logger::info("录音已停止");
    
    Logger::info("聚合设备测试完成");
} 
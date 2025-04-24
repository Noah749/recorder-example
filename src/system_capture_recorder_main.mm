#include "logger.h"
#include "audio_device_manager.h"
#include "audio_system_capture.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include <string>
#include <iostream>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <cstdio>
#include <unistd.h>

// 静态变量
static ExtAudioFileRef audioFile = nullptr;
static AudioStreamBasicDescription outputFormat;
static AudioStreamBasicDescription inputFormat;
static std::string outputFilePath;

// 静态函数
static void AudioDataCallback(const AudioBufferList* inInputData, UInt32 inNumberFrames) {
    if (!audioFile) {
        return;
    }
    
    // 写入音频数据
    OSStatus status = ExtAudioFileWrite(audioFile, inNumberFrames, inInputData);
    if (status != noErr) {
        Logger::error("写入音频数据失败: %d", (int)status);
    }
}

void TestSystemCaptureRecorder() {
    Logger::info("开始测试系统音频捕获 - 初始化阶段");

    // 初始化 AudioDeviceManager
    try {
        Logger::info("准备创建 AudioDeviceManager 实例...");
        Logger::info("AudioDeviceManager 类大小: %zu", sizeof(AudioDeviceManager));
        Logger::info("准备调用构造函数...");
        Logger::info("当前栈指针: %p", __builtin_frame_address(0));
        AudioDeviceManager manager;
        Logger::info("AudioDeviceManager 实例创建完成");

        // 获取所有聚合设备
        Logger::info("准备获取聚合设备列表...");
        auto devices = manager.GetAggregateDevices();
        Logger::info("获取到 %zu 个聚合设备", devices.size());

        // 初始化 AudioSystemCapture
        Logger::info("准备初始化 AudioSystemCapture...");
        AudioSystemCapture capture;
        Logger::info("AudioSystemCapture 初始化完成");

        // 设置输出格式
        memset(&outputFormat, 0, sizeof(outputFormat));
        outputFormat.mSampleRate = 44100;
        outputFormat.mFormatID = kAudioFormatLinearPCM;
        outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        outputFormat.mBitsPerChannel = 32;
        outputFormat.mChannelsPerFrame = 2;
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = outputFormat.mChannelsPerFrame * outputFormat.mBitsPerChannel / 8;
        outputFormat.mBytesPerPacket = outputFormat.mBytesPerFrame;

        // 使用固定文件名
        const char* filename = "system_audio.wav";
        
        // 获取当前工作目录
        char cwd[PATH_MAX];
        if (getcwd(cwd, sizeof(cwd)) != nullptr) {
            outputFilePath = std::string(cwd) + "/" + filename;
            printf("音频文件将保存到: %s\n", outputFilePath.c_str());
            Logger::info("音频文件将保存到: %s", outputFilePath.c_str());
        } else {
            outputFilePath = filename;
            printf("音频文件将保存到: %s\n", outputFilePath.c_str());
            Logger::info("音频文件将保存到: %s", outputFilePath.c_str());
        }
        
        // 创建音频文件
        CFStringRef filenameCF = CFStringCreateWithCString(kCFAllocatorDefault, outputFilePath.c_str(), kCFStringEncodingUTF8);
        CFURLRef fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                        filenameCF,
                                                        kCFURLPOSIXPathStyle,
                                                        false);
        CFRelease(filenameCF);
        
        OSStatus status = ExtAudioFileCreateWithURL(fileURL,
                                                  kAudioFileWAVEType,
                                                  &outputFormat,
                                                  nullptr,
                                                  kAudioFileFlags_EraseFile,
                                                  &audioFile);
        CFRelease(fileURL);
        
        if (status != noErr) {
            Logger::error("创建音频文件失败: %d", (int)status);
            return;
        }
        
        // 设置音频数据回调
        capture.SetAudioDataCallback(AudioDataCallback);

        // 查找并删除指定名称的设备
        auto devicesToRemove = manager.GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
        Logger::info("找到 %zu 个需要删除的聚合设备", devicesToRemove.size());

        for (const auto& deviceID : devicesToRemove) {
            auto taps = manager.GetDeviceTaps(deviceID);
            Logger::info("设备 %u 有 %zu 个 tap", (unsigned int)deviceID, taps.size());
            for (const auto& tap : taps) {
                Logger::info("正在删除 tap %u", (unsigned int)tap);
                manager.RemoveTap(tap);
            }
            Logger::info("正在删除设备 %u", (unsigned int)deviceID);
            manager.RemoveAggregateDevice(deviceID);
        }

        // 验证设备是否已删除
        auto remainingDevices = manager.GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
        Logger::info("删除后剩余 %zu 个聚合设备", remainingDevices.size());
        
        // 创建新的聚合设备
        AudioObjectID deviceID = manager.CreateAggregateDevice("plaud.ai Aggregate Audio Device");
        if (deviceID == kAudioObjectUnknown) {
            Logger::error("创建聚合设备失败");
            ExtAudioFileDispose(audioFile);
            audioFile = nullptr;
            return;
        }
        Logger::info("成功创建聚合设备，ID: %u", (unsigned int)deviceID);
        
        // 创建 tap
        AudioObjectID tapID = manager.CreateTap("plaud.ai tap");
        if (tapID == kAudioObjectUnknown) {
            Logger::error("创建 tap 失败");
            ExtAudioFileDispose(audioFile);
            audioFile = nullptr;
            return;
        }
        Logger::info("成功创建 tap，ID: %u", (unsigned int)tapID);
        
        // 添加 tap 到设备
        if (!manager.AddTapToDevice(tapID, deviceID)) {
            Logger::error("添加 tap 到设备失败");
            ExtAudioFileDispose(audioFile);
            audioFile = nullptr;
            return;
        }
        Logger::info("成功将 tap 添加到设备");

        // 设置设备ID并开始录制
        capture.SetDeviceID(deviceID);
        if (!capture.StartRecording()) {
            Logger::error("开始录制失败");
            ExtAudioFileDispose(audioFile);
            audioFile = nullptr;
            return;
        }
        Logger::info("开始录制成功");

        // 等待一段时间
        sleep(5);

        // 停止录制
        capture.StopRecording();
        Logger::info("停止录制");

        // 关闭音频文件
        ExtAudioFileDispose(audioFile);
        audioFile = nullptr;
        printf("音频文件已保存到: %s\n", outputFilePath.c_str());
        Logger::info("音频文件已保存到: %s", outputFilePath.c_str());

        // 测试完成
        Logger::info("测试完成");
    } catch (const std::exception& e) {
        Logger::error("测试过程中发生异常: %s", e.what());
    }
} 
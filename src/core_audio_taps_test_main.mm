#include "av_engine_test.h"
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

// 静态变量
static ExtAudioFileRef audioFile = nullptr;
static AudioStreamBasicDescription outputFormat;
static AudioStreamBasicDescription inputFormat;

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

void TestCoreAudioTaps() {
    @autoreleasepool {
        Logger::info("开始测试 core audio taps");

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

        // 创建音频文件
        CFURLRef fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                        CFSTR("test_audio.caf"),
                                                        kCFURLPOSIXPathStyle,
                                                        false);
        
        OSStatus status = ExtAudioFileCreateWithURL(fileURL,
                                                  kAudioFileCAFType,
                                                  &outputFormat,
                                                  nullptr,
                                                  kAudioFileFlags_EraseFile,
                                                  &audioFile);
        CFRelease(fileURL);
        
        if (status != noErr) {
            Logger::error("创建音频文件失败: %d", (int)status);
            return;
        }
        Logger::info("创建音频文件成功");

        AudioDeviceManager manager;
        AudioSystemCapture capture;

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
        AudioObjectID tapID = manager.CreateTap(@"plaud.ai tap");
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
        Logger::info("音频文件已保存");

        // 测试完成
        Logger::info("测试完成");
    }
} 
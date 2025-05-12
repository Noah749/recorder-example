#include "logger.h"
#include "audio_engine.h"
#include "audio_nodes/aec_audio_unit.h"
#include "audio_device_manager.h"
#include "audio_system_capture.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>
#import <AVFoundation/AVFoundation.h>
#import <AVFAudio/AVAudioSinkNode.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include <string>

// 全局变量
ExtAudioFileRef audioFile = nullptr;
ExtAudioFileRef micAudioFile = nullptr;
ExtAudioFileRef sourceAudioFile = nullptr;  // 新增 source 音频文件
ExtAudioFileRef mixAudioFile = nullptr;     // 新增混合音频文件
AudioStreamBasicDescription outputFormat;
AudioSystemCapture* systemCapture = nullptr;
UInt64 totalFramesWritten = 0;  // 添加全局计数器

void AudioDataCallback(const AudioBufferList* inInputData, UInt32 inNumberFrames) {
    if (!audioFile) {
        return;
    }
    
    // 直接写入音频数据
    OSStatus status = ExtAudioFileWrite(audioFile, inNumberFrames, inInputData);
    if (status != noErr) {
        Logger::error("写入音频数据失败: %d", (int)status);
    }
}

void TestAudioEngine() {
    Logger::info("开始初始化音频引擎...");
    
    // 1. 创建并初始化 AggregateDevice
    Logger::info("正在创建聚合设备...");
    AggregateDevice aggregateDevice("Plaud.ai.AggregateDevice");
    Logger::info("聚合设备创建完成");

    // 2. 创建并初始化 AudioEngine
    Logger::info("正在初始化音频引擎...");
    AudioEngine audioEngine(&aggregateDevice);
    Logger::info("音频引擎初始化完成");

    // 3. 设置输出文件路径
    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* micOutputPath = [currentDir stringByAppendingPathComponent:@"mic_audio.wav"];
    NSString* sourceOutputPath = [currentDir stringByAppendingPathComponent:@"source_audio.wav"];
    NSString* mixOutputPath = [currentDir stringByAppendingPathComponent:@"mix_audio.wav"];

    Logger::info("设置输出文件路径:");
    Logger::info("- 麦克风音频: %s", [micOutputPath UTF8String]);
    Logger::info("- 系统音频: %s", [sourceOutputPath UTF8String]);
    Logger::info("- 混合音频: %s", [mixOutputPath UTF8String]);

    audioEngine.SetOutputPaths(
        [micOutputPath UTF8String],
        [sourceOutputPath UTF8String],
        [mixOutputPath UTF8String]
    );

    // 5. 启动音频引擎
    Logger::info("正在启动音频引擎...");
    if (!audioEngine.Start()) {
        Logger::error("启动音频引擎失败，检查以下可能的原因:");
        Logger::error("1. 音频设备是否被其他应用占用");
        Logger::error("2. 系统音频服务状态");
        return;
    }

    Logger::info("音频引擎启动成功，开始录音...");

    // 6. 等待一段时间（这里等待10秒）
    Logger::info("将录制 10 秒音频...");
    sleep(10);

    // 7. 停止录音
    Logger::info("正在停止录音...");
    audioEngine.Stop();

    Logger::info("录音完成");
    Logger::info("文件保存位置:");
    Logger::info("- 麦克风音频: %s", [micOutputPath UTF8String]);
    Logger::info("- 系统音频: %s", [sourceOutputPath UTF8String]);
    Logger::info("- 混合音频: %s", [mixOutputPath UTF8String]);
}
#include "av_engine_test.h"
#include "logger.h"
#include "audio_device_manager.h"
#include "audio_system_capture.h"
#import "mac_system_audio_node.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>
#import <AVFoundation/AVFoundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include <string>

// 全局变量
ExtAudioFileRef audioFile = nullptr;
AudioStreamBasicDescription outputFormat;
AudioSystemCapture* systemCapture = nullptr;

void AudioDataCallback(const AudioBufferList* inInputData, UInt32 inNumberFrames) {
    if (!audioFile) {
        return;
    }
    
    // 写入音频数据
    OSStatus status = ExtAudioFileWrite(audioFile, inNumberFrames, inInputData);
    if (status != noErr) {
        Logger::error("写入音频数据失败: %d", (int)status);
    }
}

void TestAudioEngineTaps() {
    @autoreleasepool {
        Logger::info("开始测试 core audio taps");

        // 创建系统音频捕获
        systemCapture = new AudioSystemCapture();
        if (!systemCapture) {
            Logger::error("创建系统音频捕获失败");
            return;
        }

        // 创建设备并设置设备 ID
        if (!systemCapture->CreateTapDevice()) {
            Logger::error("创建 tap 设备失败");
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 检查设备 ID 是否有效
        AudioObjectID deviceID = systemCapture->GetDeviceID();
        if (deviceID == kAudioObjectUnknown) {
            Logger::error("设备 ID 无效");
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }
        Logger::info("设备 ID: %u", (unsigned int)deviceID);

        // 启动系统音频捕获以获取格式信息
        if (!systemCapture->StartRecording()) {
            Logger::error("启动系统音频捕获失败");
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 等待一小段时间让设备初始化
        usleep(100000); // 100ms

        // 获取音频格式
        AudioStreamBasicDescription asbd;
        if (!systemCapture->GetAudioFormat(asbd)) {
            Logger::error("获取音频格式失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        Logger::info("设备格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u",
                    asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mFormatID, asbd.mFormatFlags, asbd.mBitsPerChannel);

        // 创建音频格式
        AVAudioFormat* standardFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate: asbd.mSampleRate channels:asbd.mChannelsPerFrame];
        if (!standardFormat) {
            Logger::error("创建标准音频格式失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        Logger::info("标准格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u",
                    standardFormat.streamDescription->mSampleRate, 
                    standardFormat.streamDescription->mChannelsPerFrame,
                    standardFormat.streamDescription->mFormatID,
                    standardFormat.streamDescription->mFormatFlags,
                    standardFormat.streamDescription->mBitsPerChannel);

        // 创建音频引擎
        AVAudioEngine* audioEngine = [[AVAudioEngine alloc] init];
        if (!audioEngine) {
            Logger::error("创建音频引擎失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 获取输出节点
        AVAudioOutputNode* outputNode = [audioEngine outputNode];
        if (!outputNode) {
            Logger::error("获取输出节点失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 创建混合节点
        AVAudioMixerNode* mixerNode = [[AVAudioMixerNode alloc] init];
        if (!mixerNode) {
            Logger::error("创建混合节点失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 将节点添加到引擎
        [audioEngine attachNode:mixerNode];

        // 创建源节点
        AVAudioSourceNode* sourceNode = [[AVAudioSourceNode alloc] initWithFormat:standardFormat renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
            Logger::debug("sourceNode 开始捕获音频数据: %u 帧", (unsigned int)frameCount);
            Logger::debug("sourceNode 输出格式: 采样率=%.0f, 通道数=%u", outputData->mBuffers[0].mNumberChannels);
            Logger::debug("sourceNode 时间戳: %p", timestamp);
            Logger::debug("sourceNode 是否静音: %d", *isSilence);
            
            if (systemCapture) {
                // 计算需要读取的样本数
                size_t sampleCount = frameCount * outputData->mBuffers[0].mNumberChannels;
                
                // 从系统捕获的缓冲区读取数据
                if (systemCapture->ReadAudioData(static_cast<float*>(outputData->mBuffers[0].mData), sampleCount)) {
                    *isSilence = NO;
                } else {
                    // 如果没有足够的数据，将输出缓冲区清零
                    memset(outputData->mBuffers[0].mData, 0, sampleCount * sizeof(float));
                    *isSilence = YES;
                }
            } else {
                // 如果没有系统捕获，将输出缓冲区清零
                memset(outputData->mBuffers[0].mData, 0, frameCount * sizeof(float) * outputData->mBuffers[0].mNumberChannels);
                *isSilence = YES;
            }
            return noErr;
        }];
        
        if (!sourceNode) {
            Logger::error("创建源节点失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 将源节点添加到引擎
        [audioEngine attachNode:sourceNode];

        // 连接节点
        Logger::info("connect sourceNode to mixerNode");
        NSError* error = nil;
        
        // 直接连接节点
        [audioEngine connect:sourceNode to:mixerNode format:standardFormat];
        
        Logger::info("connect mixerNode to outputNode");
        [audioEngine connect:mixerNode to:outputNode format:standardFormat];
        Logger::info("connect done");

        // 设置输出格式
        memset(&outputFormat, 0, sizeof(outputFormat));
        outputFormat.mSampleRate = 44100;  // 使用固定的 44100 Hz 采样率
        outputFormat.mFormatID = kAudioFormatLinearPCM;
        outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        outputFormat.mBitsPerChannel = 32;
        outputFormat.mChannelsPerFrame = 2;  // 使用固定的 2 通道
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = outputFormat.mChannelsPerFrame * outputFormat.mBitsPerChannel / 8;
        outputFormat.mBytesPerPacket = outputFormat.mBytesPerFrame;

        // 创建输出文件
        NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString* outputPath = [currentDir stringByAppendingPathComponent:@"source_audio.caf"];
        NSURL* outputURL = [NSURL fileURLWithPath:outputPath];
        
        OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)outputURL,
                                                  kAudioFileCAFType,
                                                  &outputFormat,
                                                  NULL,
                                                  kAudioFileFlags_EraseFile,
                                                  &audioFile);
        if (status != noErr) {
            Logger::error("创建音频文件失败: %d", (int)status);
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 在混合节点上安装tap来获取音频
        [mixerNode installTapOnBus:0
                        bufferSize:1024
                            format:standardFormat
                             block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
            if (buffer.frameLength > 0) {
                Logger::debug("mixNode 收到音频数据: %u 帧", (unsigned int)buffer.frameLength);
                
                // 写入音频数据
                AudioBufferList audioBufferList;
                audioBufferList.mNumberBuffers = 1;
                audioBufferList.mBuffers[0].mNumberChannels = buffer.format.channelCount;
                audioBufferList.mBuffers[0].mDataByteSize = buffer.frameLength * buffer.format.channelCount * sizeof(float);
                audioBufferList.mBuffers[0].mData = buffer.floatChannelData[0];
                
                OSStatus status = ExtAudioFileWrite(audioFile, buffer.frameLength, &audioBufferList);
                if (status != noErr) {
                    Logger::error("写入音频数据失败: %d", (int)status);
                }
            }
        }];

        Logger::info("start engine");

        // 启动音频引擎
        if (![audioEngine startAndReturnError:&error]) {
            Logger::error("启动音频引擎失败: %s", [[error localizedDescription] UTF8String]);
            [mixerNode removeTapOnBus:0];
            if (audioFile) {
                ExtAudioFileDispose(audioFile);
                audioFile = nullptr;
            }
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 等待一段时间
        sleep(5);

        // 停止音频引擎
        [audioEngine stop];

        // 停止系统音频捕获
        systemCapture->StopRecording();
        delete systemCapture;
        systemCapture = nullptr;

        // 清理资源
        [mixerNode removeTapOnBus:0];
        if (audioFile) {
            ExtAudioFileDispose(audioFile);
            audioFile = nullptr;
        }
        mixerNode = nil;
        audioEngine = nil;

        Logger::info("音频已保存到: %s", [outputPath UTF8String]);
        // 测试完成
        Logger::info("测试完成");
    }
} 
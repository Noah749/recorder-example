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

        // 创建音频引擎
        AVAudioEngine* audioEngine = [[AVAudioEngine alloc] init];
        if (!audioEngine) {
            Logger::error("创建音频引擎失败");
            return;
        }

        // 获取输入节点
        AVAudioInputNode* inputNode = [audioEngine inputNode];
        if (!inputNode) {
            Logger::error("获取输入节点失败");
            return;
        }

        // 获取输入格式
        AVAudioFormat* inputFormat = [inputNode inputFormatForBus:0];
        Logger::info("输入格式: 采样率=%.0f, 通道数=%u", inputFormat.sampleRate, inputFormat.channelCount);

        // 创建混合节点
        AVAudioMixerNode* mixerNode = [[AVAudioMixerNode alloc] init];
        if (!mixerNode) {
            Logger::error("创建混合节点失败");
            return;
        }

        // 创建源节点
        AVAudioSourceNode* sourceNode = [[AVAudioSourceNode alloc] initWithFormat:inputFormat renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
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
            return;
        }

        // 将节点添加到引擎
        [audioEngine attachNode:mixerNode];
        [audioEngine attachNode:sourceNode];

        // 连接节点
        [audioEngine connect:inputNode to:mixerNode format:inputFormat];
        [audioEngine connect:sourceNode to:mixerNode format:inputFormat];

        // 设置输出格式
        outputFormat.mSampleRate = inputFormat.sampleRate;  // 使用输入设备的采样率
        outputFormat.mFormatID = kAudioFormatLinearPCM;
        outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        outputFormat.mBitsPerChannel = 32;
        outputFormat.mChannelsPerFrame = inputFormat.channelCount;  // 使用输入设备的通道数
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = outputFormat.mChannelsPerFrame * outputFormat.mBitsPerChannel / 8;
        outputFormat.mBytesPerPacket = outputFormat.mFramesPerPacket * outputFormat.mBytesPerFrame;

        // 创建输出文件
        NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString* outputPath = [currentDir stringByAppendingPathComponent:@"mixed_audio.caf"];
        NSURL* outputURL = [NSURL fileURLWithPath:outputPath];
        
        OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)outputURL,
                                                  kAudioFileCAFType,
                                                  &outputFormat,
                                                  NULL,
                                                  kAudioFileFlags_EraseFile,
                                                  &audioFile);
        if (status != noErr) {
            Logger::error("创建音频文件失败: %d", (int)status);
            return;
        }

        // 在混合节点上安装tap来获取混合后的音频
        [mixerNode installTapOnBus:0
                        bufferSize:1024
                            format:inputFormat  // 使用输入格式
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

        // 启动系统音频捕获
        if (!systemCapture->StartRecording()) {
            Logger::error("启动系统音频捕获失败");
            return;
        }

        // 启动音频引擎
        NSError* error = nil;
        if (![audioEngine startAndReturnError:&error]) {
            Logger::error("启动音频引擎失败: %s", [[error localizedDescription] UTF8String]);
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
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
dispatch_queue_t __strong audioWriteQueue = nullptr;

void AudioDataCallback(const AudioBufferList* inInputData, UInt32 inNumberFrames) {
    if (!audioFile) {
        return;
    }
    
    // 创建音频缓冲区的副本
    AudioBufferList* bufferListCopy = (AudioBufferList*)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
    bufferListCopy->mNumberBuffers = 1;
    bufferListCopy->mBuffers[0] = inInputData->mBuffers[0];
    
    // 分配数据内存并复制
    bufferListCopy->mBuffers[0].mData = malloc(inInputData->mBuffers[0].mDataByteSize);
    memcpy(bufferListCopy->mBuffers[0].mData, inInputData->mBuffers[0].mData, inInputData->mBuffers[0].mDataByteSize);
    
    // 在后台队列中写入数据
    dispatch_async(audioWriteQueue, ^{
        OSStatus status = ExtAudioFileWrite(audioFile, inNumberFrames, bufferListCopy);
        if (status != noErr) {
            Logger::error("写入音频数据失败: %d", (int)status);
        }
        
        // 释放复制的内存
        free(bufferListCopy->mBuffers[0].mData);
        free(bufferListCopy);
    });
}

void TestAudioEngineTaps() {
    @autoreleasepool {
        Logger::info("开始测试 core audio taps");

        // 创建后台写入队列
        audioWriteQueue = dispatch_queue_create("com.plaud.audio.write", DISPATCH_QUEUE_SERIAL);
        if (!audioWriteQueue) {
            Logger::error("创建写入队列失败");
            return;
        }

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

        // 设置输出节点音量为0
        [outputNode setVolume:0.0];

        // 创建混合节点
        AVAudioMixerNode* mixerNode = [audioEngine mainMixerNode];
        if (!mixerNode) {
            Logger::error("创建混合节点失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 使用标准格式
        AVAudioFormat* standardFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate: asbd.mSampleRate channels:asbd.mChannelsPerFrame];
        if (!standardFormat) {
            Logger::error("创建标准格式失败");
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

        // 创建源节点
        AVAudioSourceNode* sourceNode = [[AVAudioSourceNode alloc] initWithFormat:standardFormat renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
            if (!systemCapture) {
                memset(outputData->mBuffers[0].mData, 0, frameCount * sizeof(float) * outputData->mBuffers[0].mNumberChannels);
                *isSilence = YES;
                return noErr;
            }

            // 检查输出缓冲区
            if (!outputData || !outputData->mBuffers[0].mData) {
                Logger::error("输出缓冲区无效");
                return kAudio_ParamError;
            }

            // 计算需要读取的样本数
            size_t sampleCount = frameCount * outputData->mBuffers[0].mNumberChannels;
            size_t bufferSize = sampleCount * sizeof(float);
            
            // 确保缓冲区大小正确
            if (outputData->mBuffers[0].mDataByteSize < bufferSize) {
                Logger::error("输出缓冲区大小不足: 需要 %zu 字节，实际 %u 字节", 
                            bufferSize, outputData->mBuffers[0].mDataByteSize);
                return kAudio_ParamError;
            }

            // 从系统捕获的缓冲区读取数据
            bool success = systemCapture->ReadAudioData(static_cast<float*>(outputData->mBuffers[0].mData), sampleCount);
            if (success) {
                *isSilence = NO;
                // 验证数据是否有效
                float* data = static_cast<float*>(outputData->mBuffers[0].mData);
                bool hasValidData = false;
                for (size_t i = 0; i < sampleCount; ++i) {
                    if (data[i] != 0.0f) {
                        hasValidData = true;
                        break;
                    }
                }
                if (!hasValidData) {
                    Logger::warn("读取的数据全为零");
                }
            } else {
                // 如果没有足够的数据，将输出缓冲区清零
                memset(outputData->mBuffers[0].mData, 0, bufferSize);
                *isSilence = YES;
                Logger::warn("没有足够的数据可读");
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
        outputFormat.mSampleRate = 44100;
        outputFormat.mFormatID = kAudioFormatLinearPCM;
        outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        outputFormat.mBitsPerChannel = 32;
        outputFormat.mChannelsPerFrame = 2;
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
                        bufferSize:8192
                            format:standardFormat
                             block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
            if (buffer.frameLength > 0) {
                // 创建音频缓冲区的副本
                AudioBufferList* bufferListCopy = (AudioBufferList*)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
                bufferListCopy->mNumberBuffers = 1;
                bufferListCopy->mBuffers[0].mNumberChannels = buffer.format.channelCount;
                bufferListCopy->mBuffers[0].mDataByteSize = buffer.frameLength * buffer.format.channelCount * sizeof(float);
                bufferListCopy->mBuffers[0].mData = malloc(bufferListCopy->mBuffers[0].mDataByteSize);
                memcpy(bufferListCopy->mBuffers[0].mData, buffer.floatChannelData[0], bufferListCopy->mBuffers[0].mDataByteSize);
                
                // 在后台队列中写入数据
                dispatch_async(audioWriteQueue, ^{
                    OSStatus status = ExtAudioFileWrite(audioFile, buffer.frameLength, bufferListCopy);
                    if (status != noErr) {
                        Logger::error("写入音频数据失败: %d", (int)status);
                    }
                    
                    // 释放复制的内存
                    free(bufferListCopy->mBuffers[0].mData);
                    free(bufferListCopy);
                });
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
        audioWriteQueue = nullptr;  // ARC 会自动释放队列
        mixerNode = nil;
        audioEngine = nil;

        Logger::info("音频已保存到: %s", [outputPath UTF8String]);
        Logger::info("测试完成");
    }
} 
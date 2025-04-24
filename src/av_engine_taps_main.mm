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
#import <AVFoundation/AVFoundation.h>
#import <AVFAudio/AVAudioSinkNode.h>
#include <CoreFoundation/CoreFoundation.h>
#include <vector>
#include <string>

// 全局变量
ExtAudioFileRef audioFile = nullptr;
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

        // 获取扬声器格式
        AudioStreamBasicDescription speakerFormat;
        if (!systemCapture->GetAudioFormat(speakerFormat)) {
            Logger::error("获取扬声器格式失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        Logger::info("扬声器格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u",
                    speakerFormat.mSampleRate, speakerFormat.mChannelsPerFrame, 
                    speakerFormat.mFormatID, speakerFormat.mFormatFlags, speakerFormat.mBitsPerChannel);

        // 使用标准格式（用于扬声器）
        AVAudioFormat* standardFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:speakerFormat.mSampleRate channels:speakerFormat.mChannelsPerFrame];
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

        // 获取麦克风格式
        AVAudioInputNode* inputNode = [audioEngine inputNode];
        AVAudioFormat* micFormat = [inputNode inputFormatForBus:0];
        Logger::info("麦克风格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u",
                    micFormat.sampleRate, micFormat.channelCount,
                    micFormat.streamDescription->mFormatID,
                    micFormat.streamDescription->mFormatFlags,
                    micFormat.streamDescription->mBitsPerChannel);

        // 创建源节点 sourceNode（使用扬声器格式）
        AVAudioSourceNode* sourceNode = [[AVAudioSourceNode alloc] initWithFormat:standardFormat renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
            // 打印格式信息
            // Logger::info("sourceNode 格式信息:");
            // Logger::info("采样率: %.0f", standardFormat.sampleRate);
            // Logger::info("通道数: %u", standardFormat.channelCount);
            // Logger::info("帧数: %u", frameCount);
            // Logger::info("缓冲区大小: %u", outputData->mBuffers[0].mDataByteSize);
            
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
                } else {
                    // Logger::debug("成功读取 %zu 个样本，帧数: %u", sampleCount, frameCount);
                }
            } else {
                // 如果没有足够的数据，将输出缓冲区清零
                memset(outputData->mBuffers[0].mData, 0, bufferSize);
                *isSilence = YES;
                Logger::warn("没有足够的数据可读，样本数: %zu", sampleCount);
            }
            return noErr;
        }];

        // 创建 sinkNode
        AVAudioSinkNode* sinkNode = [[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(const AudioTimeStamp* timestamp,
                                                                                   AVAudioFrameCount frameCount,
                                                                                   const AudioBufferList* outputData) {
            // 这里写入音频文件
            if (audioFile) {
                // 创建交错格式的缓冲区
                AudioBufferList interleavedBufferList;
                interleavedBufferList.mNumberBuffers = 1;
                interleavedBufferList.mBuffers[0].mNumberChannels = outputData->mNumberBuffers;
                interleavedBufferList.mBuffers[0].mDataByteSize = frameCount * sizeof(float) * outputData->mNumberBuffers;
                interleavedBufferList.mBuffers[0].mData = malloc(interleavedBufferList.mBuffers[0].mDataByteSize);
                
                // 将非交错格式转换为交错格式
                float* interleavedData = (float*)interleavedBufferList.mBuffers[0].mData;
                for (UInt32 frame = 0; frame < frameCount; ++frame) {
                    for (UInt32 channel = 0; channel < outputData->mNumberBuffers; ++channel) {
                        float* channelData = (float*)outputData->mBuffers[channel].mData;
                        interleavedData[frame * outputData->mNumberBuffers + channel] = channelData[frame];
                    }
                }
                
                // 写入交错格式的数据
                OSStatus status = ExtAudioFileWrite(audioFile, frameCount, &interleavedBufferList);
                if (status != noErr) {
                    Logger::error("写入音频数据失败: %d", (int)status);
                }
                
                // 释放临时缓冲区
                free(interleavedBufferList.mBuffers[0].mData);
            }
            return noErr;
        }];

        // 打印 sinkNode 输入流格式
        AVAudioFormat* sinkInputFormat = [sinkNode inputFormatForBus:0];
        if (sinkInputFormat) {
            const AudioStreamBasicDescription* asbd = sinkInputFormat.streamDescription;
            Logger::info("sinkNode 输入流格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u, 每帧字节数=%u, 每包帧数=%u",
                        asbd->mSampleRate,
                        asbd->mChannelsPerFrame,
                        asbd->mFormatID,
                        asbd->mFormatFlags,
                        asbd->mBitsPerChannel,
                        asbd->mBytesPerFrame,
                        asbd->mFramesPerPacket);
        } else {
            Logger::error("无法获取 sinkNode 输入流格式");
        }

        // 1. 创建并添加所有节点到引擎
        AVAudioMixerNode* mixerNode = [[AVAudioMixerNode alloc] init];
        [audioEngine attachNode:sourceNode];
        [audioEngine attachNode:mixerNode];
        [audioEngine attachNode:sinkNode];

        // 打印各个节点的采样率
        Logger::info("inputNode 采样率: %.0f", [inputNode inputFormatForBus:0].sampleRate);
        Logger::info("sourceNode 采样率: %.0f", [sourceNode outputFormatForBus:0].sampleRate);
        Logger::info("mixerNode 采样率: %.0f", [mixerNode outputFormatForBus:0].sampleRate);
        Logger::info("sinkNode 采样率: %.0f", [sinkNode inputFormatForBus:0].sampleRate);

        // 2. 连接节点
        NSError* error = nil;
        
        // 连接 sourceNode 到 mixerNode（使用扬声器格式）
        [audioEngine connect:sourceNode to:mixerNode format:standardFormat];
        
        // 连接 inputNode 到 mixerNode（使用麦克风格式）
        [audioEngine connect:inputNode to:mixerNode format:micFormat];
        
        // 设置 mixerNode 的输出格式为双通道
        AVAudioFormat* mixerOutputFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
        [audioEngine connect:mixerNode to:sinkNode format:mixerOutputFormat];

        // 3. 设置各个节点的音量
        inputNode.volume = 0.7;
        sourceNode.volume = 0.3;
        mixerNode.outputVolume = 1.0;

        // 4. 创建输出文件
        NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString* outputPath = [currentDir stringByAppendingPathComponent:@"source_audio.wav"];
        NSURL* outputURL = [NSURL fileURLWithPath:outputPath];

        // 设置文件输出格式
        AudioStreamBasicDescription fileFormat;
        memset(&fileFormat, 0, sizeof(fileFormat));
        fileFormat.mSampleRate = standardFormat.sampleRate;
        fileFormat.mFormatID = kAudioFormatLinearPCM;
        fileFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        fileFormat.mBitsPerChannel = 32;
        fileFormat.mChannelsPerFrame = standardFormat.channelCount;
        fileFormat.mFramesPerPacket = 1;
        fileFormat.mBytesPerFrame = fileFormat.mChannelsPerFrame * (fileFormat.mBitsPerChannel / 8);
        fileFormat.mBytesPerPacket = fileFormat.mBytesPerFrame;

        // 打印文件格式信息
        Logger::info("文件格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u, 每帧字节数=%u, 每包帧数=%u",
                    fileFormat.mSampleRate,
                    fileFormat.mChannelsPerFrame,
                    fileFormat.mFormatID,
                    fileFormat.mFormatFlags,
                    fileFormat.mBitsPerChannel,
                    fileFormat.mBytesPerFrame,
                    fileFormat.mFramesPerPacket);

        // 创建音频文件
        OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)outputURL,
                                                  kAudioFileWAVEType,
                                                  &fileFormat,
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

        // 设置音频文件的客户端格式
        status = ExtAudioFileSetProperty(audioFile,
                                       kExtAudioFileProperty_ClientDataFormat,
                                       sizeof(fileFormat),
                                       &fileFormat);
        if (status != noErr) {
            Logger::error("设置音频文件客户端格式失败: %d", (int)status);
            ExtAudioFileDispose(audioFile);
            audioFile = nullptr;
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 获取并打印实际的文件格式
        UInt32 propertySize = sizeof(fileFormat);
        status = ExtAudioFileGetProperty(audioFile,
                                       kExtAudioFileProperty_FileDataFormat,
                                       &propertySize,
                                       &fileFormat);
        if (status == noErr) {
            Logger::info("实际文件格式: 采样率=%.0f, 通道数=%u, 格式ID=%u, 格式标志=%u, 位深度=%u, 每帧字节数=%u, 每包帧数=%u",
                        fileFormat.mSampleRate,
                        fileFormat.mChannelsPerFrame,
                        fileFormat.mFormatID,
                        fileFormat.mFormatFlags,
                        fileFormat.mBitsPerChannel,
                        fileFormat.mBytesPerFrame,
                        fileFormat.mFramesPerPacket);
        }

        Logger::info("start engine");

        // 启动音频引擎
        if (![audioEngine startAndReturnError:&error]) {
            Logger::error("启动音频引擎失败: %s", [[error localizedDescription] UTF8String]);
            [sourceNode removeTapOnBus:0];
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

        // 确保所有数据都已写入文件
        if (audioFile) {
            OSStatus status = ExtAudioFileDispose(audioFile);
            if (status != noErr) {
                Logger::error("关闭 tap 音频文件失败: %d", (int)status);
            } else {
                Logger::info("tap 音频文件已关闭");
            }
            audioFile = nullptr;
        }

        sourceNode = nil;
        audioEngine = nil;

        Logger::info("音频已保存到: %s", [outputPath UTF8String]);
        Logger::info("测试完成");
    }
} 
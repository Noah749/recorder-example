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

void TestAudioEngine() {
    // @autoreleasepool {
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

        // 启动系统音频捕获以获取格式信息
        if (!systemCapture->StartRecording()) {
            Logger::error("启动系统音频捕获失败");
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 等待一小段时间让设备初始化
        usleep(300000); // 300ms

        // 获取扬声器格式
        AudioStreamBasicDescription speakerFormat;
        if (!systemCapture->GetAudioFormat(speakerFormat)) {
            Logger::error("获取扬声器格式失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 使用标准格式（用于扬声器）
        AVAudioFormat* standardFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:speakerFormat.mSampleRate channels:speakerFormat.mChannelsPerFrame];
        if (!standardFormat) {
            Logger::error("创建标准格式失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

        // 获取音频格式
        AudioStreamBasicDescription asbd;
        if (!systemCapture->GetAudioFormat(asbd)) {
            Logger::error("获取音频格式失败");
            systemCapture->StopRecording();
            delete systemCapture;
            systemCapture = nullptr;
            return;
        }

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
        NSError *error = nil;
        BOOL success = [inputNode setVoiceProcessingEnabled:YES error:&error];
        if (!success) {
            Logger::error("开启语音处理失败: %s", [[error localizedDescription] UTF8String]);
        }
        Logger::info("开启语音处理成功");
        Logger::info("isVoiceProcessingAGCEnabled: %d", inputNode.isVoiceProcessingAGCEnabled);

        AVAudioFormat* micFormat = [inputNode inputFormatForBus:0];

        // 创建源节点 sourceNode（使用扬声器格式）
        AVAudioSourceNode* sourceNode = [[AVAudioSourceNode alloc] initWithFormat:standardFormat renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
            if (!systemCapture) {
                for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
                    memset(outputData->mBuffers[i].mData, 0, frameCount * sizeof(float));
                }
                *isSilence = YES;
                return noErr;
            }

            // 检查输出缓冲区
            if (!outputData || outputData->mNumberBuffers == 0) {
                Logger::error("输出缓冲区无效");
                return kAudio_ParamError;
            }

            // 创建临时缓冲区用于读取数据
            float* tempBuffer = new float[frameCount * 2];  // 双通道
            bool success = systemCapture->ReadAudioData(tempBuffer, frameCount * 2);
            
            if (success) {
                *isSilence = NO;
                for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
                    float* channelData = static_cast<float*>(outputData->mBuffers[i].mData);
                    for (UInt32 frame = 0; frame < frameCount; ++frame) {
                        channelData[frame] = tempBuffer[frame * 2 + i];
                    }
                }
            } else {
                for (UInt32 i = 0; i < outputData->mNumberBuffers; ++i) {
                    memset(outputData->mBuffers[i].mData, 0, frameCount * sizeof(float));
                }
                *isSilence = YES;
            }
            
            delete[] tempBuffer;
            return noErr;
        }];

        // 创建 sinkNode
        AVAudioSinkNode* sinkNode = [[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(const AudioTimeStamp* timestamp,
                                                                                   AVAudioFrameCount frameCount,
                                                                                   const AudioBufferList* outputData) {
            // 这里写入音频文件
            if (audioFile) {
                AudioBufferList interleavedBufferList;
                interleavedBufferList.mNumberBuffers = 1;
                interleavedBufferList.mBuffers[0].mNumberChannels = outputData->mNumberBuffers;
                interleavedBufferList.mBuffers[0].mDataByteSize = frameCount * sizeof(float) * outputData->mNumberBuffers;
                interleavedBufferList.mBuffers[0].mData = malloc(interleavedBufferList.mBuffers[0].mDataByteSize);

                float* interleavedData = (float*)interleavedBufferList.mBuffers[0].mData;
                for (UInt32 frame = 0; frame < frameCount; ++frame) {
                    for (UInt32 channel = 0; channel < outputData->mNumberBuffers; ++channel) {
                        float* channelData = (float*)outputData->mBuffers[channel].mData;
                        interleavedData[frame * outputData->mNumberBuffers + channel] = channelData[frame];
                    }
                }
                
                OSStatus status = ExtAudioFileWrite(audioFile, frameCount, &interleavedBufferList);
                if (status != noErr) {
                    Logger::error("写入音频数据失败: %d", (int)status);
                }
                
                free(interleavedBufferList.mBuffers[0].mData);
            }
            return noErr;
        }];

        // 1. 创建并添加所有节点到引擎
        AVAudioMixerNode* mixerNode = [[AVAudioMixerNode alloc] init];
        [audioEngine attachNode:sourceNode];
        [audioEngine attachNode:mixerNode];
        [audioEngine attachNode:sinkNode];

        // 2. 连接节点
        error = nil;
        
        [audioEngine connect:sourceNode to:mixerNode format:standardFormat];
        
        [audioEngine connect:inputNode to:mixerNode format:micFormat];
        
        AVAudioFormat* mixerOutputFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
        [audioEngine connect:mixerNode to:sinkNode format:mixerOutputFormat];

        inputNode.volume = 0.7;
        sourceNode.volume = 0.3;
        mixerNode.outputVolume = 1.0 * 10.0;

        // 4. 创建输出文件
        NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString* outputPath = [currentDir stringByAppendingPathComponent:@"source_audio.wav"];
        NSURL* outputURL = [NSURL fileURLWithPath:outputPath];

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
        sleep(30);

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
            }
            audioFile = nullptr;
        }

        sourceNode = nil;
        audioEngine = nil;

        Logger::info("音频已保存到: %s", [outputPath UTF8String]);
    // }
} 
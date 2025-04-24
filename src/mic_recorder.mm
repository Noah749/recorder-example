#include <iostream>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#include "mic_recorder.h"

MicRecorder::MicRecorder() {
    audioEngine_ = [[AVAudioEngine alloc] init];
    inputNode_ = [audioEngine_ inputNode];
    mixerNode_ = [[AVAudioMixerNode alloc] init];
    
    // 设置音频格式
    audioFormat_ = [[AVAudioFormat alloc] 
        initWithCommonFormat:AVAudioPCMFormatFloat32
        sampleRate:44100
        channels:1
        interleaved:NO];
        
    // 初始化 WAV 文件相关变量
    audioFile_ = nullptr;
    outputPath_ = nil;
}

MicRecorder::~MicRecorder() {
    [audioEngine_ stop];
    if (audioFile_) {
        ExtAudioFileDispose(audioFile_);
    }
}

bool MicRecorder::Start() {
    NSError* error = nil;
    
    // 设置文件输出格式
    memset(&fileFormat_, 0, sizeof(fileFormat_));
    fileFormat_.mSampleRate = 44100;
    fileFormat_.mFormatID = kAudioFormatLinearPCM;
    fileFormat_.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fileFormat_.mBitsPerChannel = 32;
    fileFormat_.mChannelsPerFrame = 1;
    fileFormat_.mFramesPerPacket = 1;
    fileFormat_.mBytesPerFrame = fileFormat_.mChannelsPerFrame * (fileFormat_.mBitsPerChannel / 8);
    fileFormat_.mBytesPerPacket = fileFormat_.mBytesPerFrame;
    
    // 创建输出文件路径
    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    outputPath_ = [currentDir stringByAppendingPathComponent:@"microphone_output.wav"];
    NSURL* outputURL = [NSURL fileURLWithPath:outputPath_];
    
    // 创建音频文件
    OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)outputURL,
                                              kAudioFileWAVEType,
                                              &fileFormat_,
                                              NULL,
                                              kAudioFileFlags_EraseFile,
                                              &audioFile_);
    if (status != noErr) {
        Logger::error("创建音频文件失败: %d", (int)status);
        return false;
    }
    
    // 设置音频文件的客户端格式
    status = ExtAudioFileSetProperty(audioFile_,
                                   kExtAudioFileProperty_ClientDataFormat,
                                   sizeof(fileFormat_),
                                   &fileFormat_);
    if (status != noErr) {
        Logger::error("设置音频文件客户端格式失败: %d", (int)status);
        ExtAudioFileDispose(audioFile_);
        audioFile_ = nullptr;
        return false;
    }
    
    // 创建 sinkNode
    sinkNode_ = [[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(const AudioTimeStamp* timestamp,
                                                                       AVAudioFrameCount frameCount,
                                                                       const AudioBufferList* outputData) {
        if (audioFile_) {
            // 写入音频数据
            OSStatus status = ExtAudioFileWrite(audioFile_, frameCount, outputData);
            if (status != noErr) {
                Logger::error("写入音频数据失败: %d", (int)status);
            }
        }
        return noErr;
    }];
    
    // 将输入节点连接到混音器
    [audioEngine_ attachNode:mixerNode_];
    [audioEngine_ connect:inputNode_ to:mixerNode_ format:audioFormat_];
    
    // 将混音器连接到 sinkNode
    [audioEngine_ attachNode:sinkNode_];
    [audioEngine_ connect:mixerNode_ to:sinkNode_ format:audioFormat_];
    
    // 启动引擎
    if (![audioEngine_ startAndReturnError:&error]) {
        Logger::error("启动 AVAudioEngine 失败: %s", [[error localizedDescription] UTF8String]);
        ExtAudioFileDispose(audioFile_);
        audioFile_ = nullptr;
        return false;
    }
    
    Logger::info("AVAudioEngine 已启动，正在录制到: %s", [outputPath_ UTF8String]);
    return true;
}

void MicRecorder::Stop() {
    [audioEngine_ stop];
    if (audioFile_) {
        ExtAudioFileDispose(audioFile_);
        audioFile_ = nullptr;
        Logger::info("音频已保存到: %s", [outputPath_ UTF8String]);
    }
    Logger::info("AVAudioEngine 已停止");
}

void MicRecorder::SetVolume(float volume) {
    mixerNode_.volume = volume;
} 
#include <iostream>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#include "av_engine_test.h"

AVAudioEngineTest::AVAudioEngineTest() {
    audioEngine_ = [[AVAudioEngine alloc] init];
    inputNode_ = [audioEngine_ inputNode];
    outputNode_ = [audioEngine_ outputNode];
    mixerNode_ = [[AVAudioMixerNode alloc] init];
    
    // 设置音频格式
    audioFormat_ = [[AVAudioFormat alloc] 
        initWithCommonFormat:AVAudioPCMFormatFloat32
        sampleRate:44100
        channels:1
        interleaved:NO];
}

AVAudioEngineTest::~AVAudioEngineTest() {
    [audioEngine_ stop];
}

bool AVAudioEngineTest::Start() {
    NSError* error = nil;
    
    // 将输入节点连接到混音器
    [audioEngine_ attachNode:mixerNode_];
    [audioEngine_ connect:inputNode_ to:mixerNode_ format:audioFormat_];
    
    // 将混音器连接到输出节点
    [audioEngine_ connect:mixerNode_ to:outputNode_ format:audioFormat_];
    
    // 启动引擎
    if (![audioEngine_ startAndReturnError:&error]) {
        Logger::error("启动 AVAudioEngine 失败: %s", [[error localizedDescription] UTF8String]);
        return false;
    }
    
    Logger::info("AVAudioEngine 已启动");
    return true;
}

void AVAudioEngineTest::Stop() {
    [audioEngine_ stop];
    Logger::info("AVAudioEngine 已停止");
}

void AVAudioEngineTest::SetVolume(float volume) {
    mixerNode_.volume = volume;
} 
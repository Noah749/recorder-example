#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#endif

#include "audio_system_capture.h"
#include "audio_device_manager.h"

#ifdef __OBJC__

/**
 * @class MacSystemAudioNode
 * @brief 系统音频捕获节点，继承自AVAudioSourceNode
 * 用于捕获系统音频输出并转发到音频引擎
 */
@interface MacSystemAudioNode : AVAudioSourceNode {
    AudioSystemCapture* _systemCapture;    ///< 系统音频捕获器
    AVAudioEngine* _engine;                ///< 音频引擎引用
    AudioDeviceManager* _deviceManager;    ///< 音频设备管理器
    AudioObjectID _deviceID;               ///< 聚合设备ID
    AudioObjectID _tapID;                  ///< 音频Tap ID
    BOOL _isCapturing;                     ///< 是否正在捕获
    BOOL _isRecording;                     ///< 是否正在录制
    AVAudioFormat* _outputFormat;          ///< 输出音频格式
}

/// 是否正在录制
@property (nonatomic, assign) BOOL isRecording;

/// 输出音频格式
@property (nonatomic, strong) AVAudioFormat* outputFormat;

/**
 * @brief 创建节点实例
 * @param engine 音频引擎实例
 * @return 节点实例
 */
+ (instancetype)nodeWithEngine:(AVAudioEngine*)engine;

/**
 * @brief 初始化方法
 * @param format 音频格式
 * @return 节点实例
 */
- (instancetype)initWithFormat:(AVAudioFormat*)format;

/// 获取设备管理器
- (AudioDeviceManager*)deviceManager;

/// 获取设备ID
- (AudioObjectID)deviceID;

/**
 * @brief 设置音频设备
 * @return 是否设置成功
 */
- (BOOL)setupAudioDevice;

/// 开始捕获
- (void)startCapture;

/// 停止捕获
- (void)stopCapture;

/// 处理引擎状态变化
- (void)handleEngineStateChange:(AVAudioEngine*)audioEngine;

/// 配置输出格式
- (void)configureOutputFormat:(AVAudioFormat*)format;

/// 处理音频数据
- (void)processAudioBuffer:(AVAudioPCMBuffer*)buffer atTime:(AVAudioTime*)time;

/// 连接到目标节点
- (BOOL)connectToNode:(AVAudioNode*)node format:(AVAudioFormat*)format;

@end
#endif 
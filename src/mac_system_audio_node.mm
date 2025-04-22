#import "mac_system_audio_node.h"
#include "logger.h"
#include "audio_device_manager.h"

@implementation MacSystemAudioNode

+ (instancetype)nodeWithEngine:(AVAudioEngine*)engine {
    if (!engine) {
        Logger::error("MacSystemAudioNode: 无效的音频引擎");
        return nil;
    }
    
    Logger::debug("MacSystemAudioNode: 开始创建实例");
    
    // 创建音频格式
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    
    // 创建节点
    MacSystemAudioNode* node = [[super alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        // 这里处理音频渲染
        *isSilence = NO;
        return noErr;
    }];
    
    Logger::debug("MacSystemAudioNode: alloc 结果: %p", node);
    if (!node) {
        Logger::error("MacSystemAudioNode: 创建实例失败");
        return nil;
    }
    
    // 初始化成员变量
    node->_engine = engine;
    Logger::debug("MacSystemAudioNode: 设置引擎: %p", engine);
    
    node->_systemCapture = new AudioSystemCapture();
    Logger::debug("MacSystemAudioNode: AudioSystemCapture创建结果: %p", node->_systemCapture);
    if (!node->_systemCapture) {
        Logger::error("MacSystemAudioNode: 创建AudioSystemCapture失败");
        return nil;
    }
    
    node->_deviceManager = new AudioDeviceManager();
    Logger::debug("MacSystemAudioNode: AudioDeviceManager创建结果: %p", node->_deviceManager);
    if (!node->_deviceManager) {
        Logger::error("MacSystemAudioNode: 创建AudioDeviceManager失败");
        delete node->_systemCapture;
        return nil;
    }
    
    node->_isCapturing = NO;
    node->_isRecording = NO;
    node->_deviceID = kAudioObjectUnknown;
    node->_tapID = kAudioObjectUnknown;
    node->_outputFormat = format;
    Logger::debug("MacSystemAudioNode: 成员变量初始化完成");
    
    // 初始化设备
    Logger::debug("MacSystemAudioNode: 开始初始化设备");
    BOOL setupSuccess = [node setupAudioDevice];
    if (!setupSuccess) {
        Logger::error("MacSystemAudioNode: 设备初始化失败");
        [node cleanup];
        return nil;
    }
    Logger::debug("MacSystemAudioNode: 设备初始化完成");
    
    // 将节点添加到引擎
    [engine attachNode:node];
    Logger::debug("MacSystemAudioNode: 节点已添加到引擎");
    
    Logger::info("MacSystemAudioNode: 实例创建成功");
    return node;
}

- (void)cleanup {
    [self stopCapture];
    
    if (_systemCapture) {
        delete _systemCapture;
        _systemCapture = nullptr;
    }
    if (_deviceManager) {
        delete _deviceManager;
        _deviceManager = nullptr;
    }
}

- (instancetype)init {
    Logger::debug("MacSystemAudioNode: 开始init");
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    self = [super initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        *isSilence = NO;
        return noErr;
    }];
    Logger::debug("MacSystemAudioNode: super init结果: %p", self);
    if (self) {
        _engine = nil;
        _systemCapture = nullptr;
        _deviceManager = nullptr;
        _deviceID = kAudioObjectUnknown;
        _tapID = kAudioObjectUnknown;
        _isCapturing = NO;
        _isRecording = NO;
        _outputFormat = format;
        Logger::debug("MacSystemAudioNode: init完成");
    }
    return self;
}

- (AudioDeviceManager*)deviceManager {
    return _deviceManager;
}

- (AudioObjectID)deviceID {
    return _deviceID;
}

- (BOOL)isRecording {
    return _isRecording;
}

- (void)setIsRecording:(BOOL)isRecording {
    _isRecording = isRecording;
}

- (BOOL)setupAudioDevice {
    Logger::debug("MacSystemAudioNode: 开始设置音频设备");
    
    // 清理现有设备
    auto devicesToRemove = _deviceManager->GetAggregateDevicesByName("plaud.ai Aggregate Audio Device");
    Logger::info("找到 %zu 个需要删除的聚合设备", devicesToRemove.size());
    
    for (const auto& deviceID : devicesToRemove) {
        auto taps = _deviceManager->GetDeviceTaps(deviceID);
        Logger::info("设备 %u 有 %zu 个 tap", (unsigned int)deviceID, taps.size());
        for (const auto& tap : taps) {
            Logger::info("正在删除 tap %u", (unsigned int)tap);
            _deviceManager->RemoveTap(tap);
        }
        Logger::info("正在删除设备 %u", (unsigned int)deviceID);
        _deviceManager->RemoveAggregateDevice(deviceID);
    }
    
    // 创建新设备
    _deviceID = _deviceManager->CreateAggregateDevice("plaud.ai Aggregate Audio Device");
    if (_deviceID == kAudioObjectUnknown) {
        Logger::error("创建聚合设备失败");
        return NO;
    }
    Logger::info("成功创建聚合设备，ID: %u", (unsigned int)_deviceID);
    
    // 创建并配置tap
    _tapID = _deviceManager->CreateTap(@"plaud.ai tap");
    if (_tapID == kAudioObjectUnknown) {
        Logger::error("创建 tap 失败");
        return NO;
    }
    Logger::info("成功创建 tap，ID: %u", (unsigned int)_tapID);
    
    if (!_deviceManager->AddTapToDevice(_tapID, _deviceID)) {
        Logger::error("添加 tap 到设备失败");
        return NO;
    }
    Logger::info("成功将 tap 添加到设备");
    
    Logger::debug("MacSystemAudioNode: 音频设备设置完成");
    return YES;
}

- (void)configureOutputFormat:(AVAudioFormat*)format {
    if (!format) {
        Logger::error("MacSystemAudioNode: 无效的输出格式");
        return;
    }
    
    _outputFormat = format;
    Logger::info("MacSystemAudioNode: 已配置输出格式: %@", format);
}

- (void)processAudioBuffer:(AVAudioPCMBuffer*)buffer atTime:(AVAudioTime*)time {
    if (!buffer || !time) {
        Logger::error("MacSystemAudioNode: 无效的音频数据或时间");
        return;
    }
    
    if (!_isCapturing) {
        return;
    }
    
    // 检查音频格式是否匹配
    if (![_outputFormat isEqual:buffer.format]) {
        Logger::error("MacSystemAudioNode: 音频格式不匹配");
        return;
    }
    
    // 处理音频数据
    if (buffer.frameLength > 0) {
        Logger::debug("处理音频数据: %u 帧", (unsigned int)buffer.frameLength);
        // 这里可以添加自定义的音频处理逻辑
    }
}

- (void)startCapture {
    if (_isCapturing) {
        return;
    }
    
    if (_deviceID == kAudioObjectUnknown) {
        Logger::error("MacSystemAudioNode: 无效的设备ID");
        return;
    }
    
    // 确保输出格式已配置
    if (!_outputFormat) {
        _outputFormat = [self outputFormatForBus:0];
        Logger::info("MacSystemAudioNode: 使用默认输出格式");
    }
    
    _systemCapture->SetDeviceID(_deviceID);
    if (!_systemCapture->StartRecording()) {
        Logger::error("MacSystemAudioNode: 启动系统音频捕获失败");
        return;
    }
    
    _isCapturing = YES;
    self.isRecording = YES;
    
    // 安装音频Tap
    [self installTapOnBus:0 
               bufferSize:1024 
                   format:_outputFormat
                    block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [self processAudioBuffer:buffer atTime:when];
    }];
    
    Logger::info("MacSystemAudioNode: 系统音频捕获已启动");
}

- (void)stopCapture {
    if (!_isCapturing) {
        return;
    }
    
    [self removeTapOnBus:0];
    _systemCapture->StopRecording();
    _isCapturing = NO;
    self.isRecording = NO;
    
    Logger::info("MacSystemAudioNode: 系统音频捕获已停止");
}

- (void)handleEngineStateChange:(AVAudioEngine *)audioEngine {
    if (!audioEngine) {
        return;
    }
    
    if (audioEngine.isRunning) {
        [self startCapture];
    } else {
        [self stopCapture];
    }
}

- (BOOL)connectToNode:(AVAudioNode*)node format:(AVAudioFormat*)format {
    if (!node || !_engine) {
        Logger::error("MacSystemAudioNode: 无效的节点或引擎");
        return NO;
    }
    
    if (!format) {
        format = _outputFormat;
    }
    
    Logger::debug("MacSystemAudioNode: 开始连接节点");
    [_engine connect:self to:node format:format];
    Logger::debug("MacSystemAudioNode: 节点连接完成");
    
    return YES;
}

@end 
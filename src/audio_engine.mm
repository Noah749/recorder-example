#import "audio_engine.h"
#import "audio_nodes/audio_nodes.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>

AudioEngine::AudioEngine(AggregateDevice* aggregateDevice)
    : audioEngine_(nullptr)
    , inputNode_(nullptr)
    , sourceNode_(nullptr)
    , mixerNode_(nullptr)
    , sinkNode_(nullptr)
    , aecAudioUnit_(nullptr)
    , systemCapture_(nullptr)
    , aggregateDevice_(aggregateDevice)
    , standardFormat_(nullptr)
    , micFormat_(nullptr)
    , mixerOutputFormat_(nullptr)
    , micAudioFile_(nullptr)
    , sourceAudioFile_(nullptr)
    , mixAudioFile_(nullptr)
    , isRunning_(false)
    , isPaused_(false) {
}

AudioEngine::~AudioEngine() {
    Stop();
}

bool AudioEngine::Initialize() { 
    if (aggregateDevice_ == nullptr) {
        Logger::error("聚合设备为空");
        return false;
    }
    // 创建系统音频捕获
    systemCapture_ = new AudioSystemCapture(aggregateDevice_);
    if (!systemCapture_) {
        Logger::error("创建系统音频捕获失败");
        return false;
    }
    
    // 检查设备 ID 是否有效
    AudioObjectID deviceID = systemCapture_->GetDeviceID();
    if (deviceID == kAudioObjectUnknown) {
        Logger::error("设备 ID 无效");
        delete systemCapture_;
        systemCapture_ = nullptr;
        return false;
    }
    
    // 启动系统音频捕获以获取格式信息
    if (!systemCapture_->StartRecording()) {
        Logger::error("启动系统音频捕获失败");
        delete systemCapture_;
        systemCapture_ = nullptr;
        return false;
    }
    
    // 获取音频格式
    AudioStreamBasicDescription asbd;
    if (!systemCapture_->GetAudioFormat(asbd)) {
        Logger::error("获取音频格式失败");
        systemCapture_->StopRecording();
        delete systemCapture_;
        systemCapture_ = nullptr;
        return false;
    }
    
    Logger::info("系统音频 - 采样率: %f, 声道数: %d", asbd.mSampleRate, asbd.mChannelsPerFrame);
    
    // 设置音频格式
    SetupAudioFormats();
    
    return true;
}

void AudioEngine::SetupAudioFormats() {
    Logger::info("设置音频格式");
    // 获取系统音频格式
    AudioStreamBasicDescription asbd;
    if (!systemCapture_->GetAudioFormat(asbd)) {
        Logger::error("获取系统音频格式失败");
        return;
    }
    
    // 使用系统音频格式创建标准格式
    standardFormat_ = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:asbd.mSampleRate channels:asbd.mChannelsPerFrame];
    if (!standardFormat_) {
        Logger::error("创建标准格式失败");
        return;
    }
    Logger::info("标准格式 - 采样率: %f, 声道数: %d", standardFormat_.sampleRate, standardFormat_.channelCount);
    
    // 获取麦克风格式
    micFormat_ = [inputNode_ inputFormatForBus:0];
    Logger::info("麦克风格式 - 采样率: %f, 声道数: %d", micFormat_.sampleRate, micFormat_.channelCount);
    
    // 设置混音器输出格式
    mixerOutputFormat_ = [[AVAudioFormat alloc] initStandardFormatWithSampleRate: micFormat_.sampleRate channels: 2];
    Logger::info("混音器输出格式 - 采样率: %f, 声道数: %d", mixerOutputFormat_.sampleRate, mixerOutputFormat_.channelCount);
}

bool AudioEngine::Prepare() {
    // 创建音频引擎
    audioEngine_ = [[AVAudioEngine alloc] init];
    if (!audioEngine_) {
        Logger::error("创建音频引擎失败");
        return false;
    }
    
    // 创建音频节点
    if (!CreateNodes()) {
        return false;
    }
    
    // 连接音频节点
    if (!ConnectNodes()) {
        return false;
    }
    
    return true;
}

bool AudioEngine::CreateNodes() {
    // 获取输入节点
    inputNode_ = [audioEngine_ inputNode];
    if (!inputNode_) {
        Logger::error("获取输入节点失败");
        return false;
    }
    
    // 创建源节点
    sourceNode_ = [[AVAudioSourceNode alloc] initWithFormat:standardFormat_ renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp, AVAudioFrameCount frameCount, AudioBufferList* outputData) {
        if (!systemCapture_) {
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
        bool success = systemCapture_->ReadAudioData(tempBuffer, frameCount * 2);
        
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
    
    // 创建混音器节点
    mixerNode_ = [[AVAudioMixerNode alloc] init];
    
    // 创建 AEC 音频单元
    AECAudioNode *aecAudioNode = [[AECAudioNode alloc] init];
    NSError *error = nil;
    if (![aecAudioNode initializeWithError:&error]) {
        Logger::error("初始化 AECAudioNode 失败: %s", error.localizedDescription.UTF8String);
        return false;
    }
    
    // 获取 AVAudioUnit
    aecAudioUnit_ = aecAudioNode.audioUnit;
    
    // 创建接收节点
    sinkNode_ = [[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(const AudioTimeStamp* timestamp,
                                                                       AVAudioFrameCount frameCount,
                                                                       const AudioBufferList* outputData) {
        // 写入音频文件
        if (mixAudioFile_) {
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
            
            OSStatus status = ExtAudioFileWrite(mixAudioFile_, frameCount, &interleavedBufferList);
            if (status != noErr) {
                Logger::error("写入音频数据失败: %d", (int)status);
            }
            
            free(interleavedBufferList.mBuffers[0].mData);
        }
        return noErr;
    }];
    
    // 添加节点到引擎
    [audioEngine_ attachNode:sourceNode_];
    [audioEngine_ attachNode:mixerNode_];
    [audioEngine_ attachNode:sinkNode_];
    [audioEngine_ attachNode:aecAudioUnit_];
    
    // 为麦克风输入节点安装 tap
    Logger::info("正在为麦克风输入节点安装 tap...");
    void (^tapBlock)(AVAudioPCMBuffer * _Nonnull, AVAudioTime * _Nonnull) = ^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                if (micAudioFile_) {
                    Logger::info("收到麦克风数据: %d 帧", (int)buffer.frameLength);
                    // 创建临时缓冲区用于格式转换
                    AudioBufferList interleavedBufferList;
                    interleavedBufferList.mNumberBuffers = 1;
                    interleavedBufferList.mBuffers[0].mNumberChannels = buffer.format.channelCount;
                    interleavedBufferList.mBuffers[0].mDataByteSize = buffer.frameLength * sizeof(float) * buffer.format.channelCount;
                    interleavedBufferList.mBuffers[0].mData = malloc(interleavedBufferList.mBuffers[0].mDataByteSize);

                    float* interleavedData = (float*)interleavedBufferList.mBuffers[0].mData;
                    for (UInt32 frame = 0; frame < buffer.frameLength; ++frame) {
                        for (UInt32 channel = 0; channel < buffer.format.channelCount; ++channel) {
                            float* channelData = (float*)buffer.audioBufferList->mBuffers[channel].mData;
                            interleavedData[frame * buffer.format.channelCount + channel] = channelData[frame];
                        }
                    }

                    OSStatus status = ExtAudioFileWrite(micAudioFile_, buffer.frameLength, &interleavedBufferList);
                    if (status != noErr) {
                        Logger::error("写入麦克风音频数据失败: %d", (int)status);
                    }

                    free(interleavedBufferList.mBuffers[0].mData);
                }
    };
            
    [inputNode_ installTapOnBus:0 bufferSize:1024 format: micFormat_ block:tapBlock];
    Logger::info("麦克风输入节点 tap 安装完成");
        
    // 为系统音频源节点安装 tap
    Logger::info("正在为系统音频源节点安装 tap...");
    [sourceNode_ installTapOnBus:0 bufferSize:1024 format:standardFormat_ block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        Logger::info("收到系统音频数据: %d 帧", (int)buffer.frameLength);
        if (sourceAudioFile_) {
            // 创建临时缓冲区用于格式转换
            AudioBufferList interleavedBufferList;
            interleavedBufferList.mNumberBuffers = 1;
            interleavedBufferList.mBuffers[0].mNumberChannels = buffer.format.channelCount;
            interleavedBufferList.mBuffers[0].mDataByteSize = buffer.frameLength * sizeof(float) * buffer.format.channelCount;
            interleavedBufferList.mBuffers[0].mData = malloc(interleavedBufferList.mBuffers[0].mDataByteSize);

            float* interleavedData = (float*)interleavedBufferList.mBuffers[0].mData;
            for (UInt32 frame = 0; frame < buffer.frameLength; ++frame) {
                for (UInt32 channel = 0; channel < buffer.format.channelCount; ++channel) {
                    float* channelData = (float*)buffer.audioBufferList->mBuffers[channel].mData;
                    interleavedData[frame * buffer.format.channelCount + channel] = channelData[frame];
                }
            }

            OSStatus status = ExtAudioFileWrite(sourceAudioFile_, buffer.frameLength, &interleavedBufferList);
            if (status != noErr) {
                Logger::error("写入 source 音频数据失败: %d", (int)status);
            }

            free(interleavedBufferList.mBuffers[0].mData);
        }
    }];
    Logger::info("系统音频源节点 tap 安装完成");
        
    return true;
}

bool AudioEngine::ConnectNodes() {
    NSError *error = nil;
    
    // 连接节点
    [audioEngine_ connect:sourceNode_ to:mixerNode_ format:standardFormat_];
    [audioEngine_ connect:inputNode_ to:aecAudioUnit_ format:micFormat_];
    [audioEngine_ connect:aecAudioUnit_ to:mixerNode_ format:standardFormat_];
    [audioEngine_ connect:mixerNode_ to:sinkNode_ format:mixerOutputFormat_];
    
    // 设置音量
    inputNode_.volume = 0.5;
    sourceNode_.volume = 0.5;
    mixerNode_.outputVolume = 1.0;
    
    return true;
}

bool AudioEngine::CreateAudioFiles() {
    // 创建麦克风音频文件
    AudioStreamBasicDescription micFileFormat;
    memset(&micFileFormat, 0, sizeof(micFileFormat));
    micFileFormat.mSampleRate = micFormat_.sampleRate;
    micFileFormat.mFormatID = kAudioFormatLinearPCM;
    micFileFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    micFileFormat.mBitsPerChannel = 32;
    micFileFormat.mChannelsPerFrame = micFormat_.channelCount;
    micFileFormat.mFramesPerPacket = 1;
    micFileFormat.mBytesPerFrame = micFileFormat.mChannelsPerFrame * (micFileFormat.mBitsPerChannel / 8);
    micFileFormat.mBytesPerPacket = micFileFormat.mBytesPerFrame;

    Logger::info("麦克风音频文件格式参数:");
    Logger::info("- 采样率: %.0f Hz", micFileFormat.mSampleRate);
    Logger::info("- 声道数: %d", micFileFormat.mChannelsPerFrame);
    Logger::info("- 位深: %d bits", micFileFormat.mBitsPerChannel);
    Logger::info("- 每帧字节数: %d bytes", micFileFormat.mBytesPerFrame);
    Logger::info("- 每包字节数: %d bytes", micFileFormat.mBytesPerPacket);
    
    NSURL* micOutputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:micOutputPath_.c_str()]];
    Logger::info("麦克风输出文件路径: %s", micOutputPath_.c_str());
    
    OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)micOutputURL,
                                              kAudioFileWAVEType,
                                              &micFileFormat,
                                              NULL,
                                              kAudioFileFlags_EraseFile,
                                              &micAudioFile_);
    if (status != noErr) {
        Logger::error("创建麦克风音频文件失败: %d", (int)status);
        Logger::error("检查以下可能的原因:");
        Logger::error("1. 文件路径是否有效");
        Logger::error("2. 是否有写入权限");
        Logger::error("3. 音频格式参数是否正确");
        Logger::error("4. 磁盘空间是否足够");
        return false;
    }
    Logger::info("麦克风音频文件创建成功");
    
    // 创建源音频文件
    AudioStreamBasicDescription sourceFileFormat;
    memset(&sourceFileFormat, 0, sizeof(sourceFileFormat));
    sourceFileFormat.mSampleRate = standardFormat_.sampleRate;
    sourceFileFormat.mFormatID = kAudioFormatLinearPCM;
    sourceFileFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    sourceFileFormat.mBitsPerChannel = 32;
    sourceFileFormat.mChannelsPerFrame = standardFormat_.channelCount;
    sourceFileFormat.mFramesPerPacket = 1;
    sourceFileFormat.mBytesPerFrame = sourceFileFormat.mChannelsPerFrame * (sourceFileFormat.mBitsPerChannel / 8);
    sourceFileFormat.mBytesPerPacket = sourceFileFormat.mBytesPerFrame;
    
    NSURL* sourceOutputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:sourceOutputPath_.c_str()]];
    status = ExtAudioFileCreateWithURL((__bridge CFURLRef)sourceOutputURL,
                                     kAudioFileWAVEType,
                                     &sourceFileFormat,
                                     NULL,
                                     kAudioFileFlags_EraseFile,
                                     &sourceAudioFile_);
    if (status != noErr) {
        Logger::error("创建源音频文件失败: %d", (int)status);
        return false;
    }
    
    // 创建混合音频文件
    AudioStreamBasicDescription mixFileFormat;
    memset(&mixFileFormat, 0, sizeof(mixFileFormat));
    mixFileFormat.mSampleRate = micFormat_.sampleRate;
    mixFileFormat.mFormatID = kAudioFormatLinearPCM;
    mixFileFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    mixFileFormat.mBitsPerChannel = 32;
    mixFileFormat.mChannelsPerFrame = 2;  // 立体声
    mixFileFormat.mFramesPerPacket = 1;
    mixFileFormat.mBytesPerFrame = mixFileFormat.mChannelsPerFrame * (mixFileFormat.mBitsPerChannel / 8);
    mixFileFormat.mBytesPerPacket = mixFileFormat.mBytesPerFrame;
    
    NSURL* mixOutputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:mixOutputPath_.c_str()]];
    status = ExtAudioFileCreateWithURL((__bridge CFURLRef)mixOutputURL,
                                     kAudioFileWAVEType,
                                     &mixFileFormat,
                                     NULL,
                                     kAudioFileFlags_EraseFile,
                                     &mixAudioFile_);
    if (status != noErr) {
        Logger::error("创建混合音频文件失败: %d", (int)status);
        return false;
    }
    
    return true;
}

void AudioEngine::CleanupAudioFiles() {
    if (micAudioFile_) {
        ExtAudioFileDispose(micAudioFile_);
        micAudioFile_ = nullptr;
    }
    
    if (sourceAudioFile_) {
        ExtAudioFileDispose(sourceAudioFile_);
        sourceAudioFile_ = nullptr;
    }
    
    if (mixAudioFile_) {
        ExtAudioFileDispose(mixAudioFile_);
        mixAudioFile_ = nullptr;
    }
}

bool AudioEngine::Start() {
    if (isRunning_) {
        return true;
    }

    if (!Initialize()) {
        Logger::error("初始化失败");
        return false;
    }
    
    // 创建音频文件
    if (!CreateAudioFiles()) {
        Logger::error("创建音频文件失败");
        return false;
    }
    
    NSError *error = nil;
    if (![audioEngine_ startAndReturnError:&error]) {
        Logger::error("启动音频引擎失败: %s", [[error localizedDescription] UTF8String]);
        return false;
    }
    
    isRunning_ = true;
    isPaused_ = false;
    Logger::info("音频引擎启动成功");
    
    return true;
}

void AudioEngine::Pause() {
    if (!isRunning_ || isPaused_) {
        return;
    }
    
    [audioEngine_ pause];
    isPaused_ = true;
    Logger::info("音频引擎已暂停");
}

void AudioEngine::Resume() {
    if (!isRunning_ || !isPaused_) {
        return;
    }
    
    NSError *error = nil;
    if (![audioEngine_ startAndReturnError:&error]) {
        Logger::error("恢复音频引擎失败: %s", [[error localizedDescription] UTF8String]);
        return;
    }
    
    isPaused_ = false;
    Logger::info("音频引擎已恢复");
}

void AudioEngine::Stop() {
    if (!isRunning_) {
        return;
    }
    
    // 移除 tap
    if (inputNode_) {
        [inputNode_ removeTapOnBus:0];
    }
    if (sourceNode_) {
        [sourceNode_ removeTapOnBus:0];
    }
    
    // 停止音频引擎
    [audioEngine_ stop];
    
    // 停止系统音频捕获
    if (systemCapture_) {
        systemCapture_->StopRecording();
        delete systemCapture_;
        systemCapture_ = nullptr;
    }
    
    // 清理音频文件
    CleanupAudioFiles();
    
    // 释放资源
    sourceNode_ = nil;
    audioEngine_ = nil;
    
    isRunning_ = false;
    isPaused_ = false;
    Logger::info("音频引擎已停止");
}

void AudioEngine::SetOutputPaths(const std::string& micPath, 
                               const std::string& sourcePath,
                               const std::string& mixPath) {
    micOutputPath_ = micPath;
    sourceOutputPath_ = sourcePath;
    mixOutputPath_ = mixPath;
}

bool AudioEngine::IsRunning() const {
    return isRunning_;
} 
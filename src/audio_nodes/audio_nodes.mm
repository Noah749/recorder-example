#import "audio_nodes.h"

@implementation AECUnit {
    AudioBufferList *_inputBufferList;
    AudioBufferList *_outputBufferList;
    AURenderBlock _renderBlock;
    AUAudioUnitBus *_inputBus;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_inputBusArray;
    AUAudioUnitBusArray *_outputBusArray;
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription error:outError];
    if (self) {
        _inputBufferList = NULL;
        _outputBufferList = NULL;
        
        // 创建输入和输出总线，初始格式将在连接时设置
        AVAudioFormat *defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
        
        _inputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:outError];
        _outputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:outError];
        
        if (!_inputBus || !_outputBus) {
            return nil;
        }
        
        // 创建总线数组
        _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                              busType:AUAudioUnitBusTypeInput
                                                               busses:@[_inputBus]];
        
        _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                               busType:AUAudioUnitBusTypeOutput
                                                                busses:@[_outputBus]];
        
        // 设置渲染回调
        __weak typeof(self) weakSelf = self;
        _renderBlock = ^AUAudioUnitStatus(AudioUnitRenderActionFlags * _Nonnull actionFlags,
                                       const AudioTimeStamp * _Nonnull timestamp,
                                       AUAudioFrameCount frameCount,
                                       NSInteger outputBusNumber,
                                       AudioBufferList * _Nonnull outputData,
                                       AURenderPullInputBlock _Nullable pullInputBlock) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return kAudioUnitErr_FailedInitialization;
            }
            
            // 从输入总线获取音频数据
            AudioUnitRenderActionFlags pullFlags = 0;
            AUAudioUnitStatus status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, strongSelf->_inputBufferList);
            if (status != noErr) {
                return status;
            }
            
            // 处理声道数转换：将单声道数据复制到双声道的两个通道
            if (strongSelf->_inputBufferList->mNumberBuffers == 1 && outputData->mNumberBuffers == 2) {
                float* inputData = (float*)strongSelf->_inputBufferList->mBuffers[0].mData;
                float* leftChannel = (float*)outputData->mBuffers[0].mData;
                float* rightChannel = (float*)outputData->mBuffers[1].mData;
                
                for (UInt32 frame = 0; frame < frameCount; ++frame) {
                    leftChannel[frame] = inputData[frame];
                    rightChannel[frame] = inputData[frame];  // 将相同的音频数据复制到两个通道
                }
            } else {
                // 如果声道数相同，直接复制
                for (UInt32 channel = 0; channel < outputData->mNumberBuffers; ++channel) {
                    memcpy(outputData->mBuffers[channel].mData,
                          strongSelf->_inputBufferList->mBuffers[channel].mData,
                          frameCount * sizeof(float));
                }
            }
            
            return noErr;
        };
    }
    return self;
}

- (void)setInputFormat:(AVAudioFormat *)format forBus:(AUAudioUnitBus *)bus {
    NSLog(@"设置输入格式: 采样率=%f, 声道数=%d", format.sampleRate, (int)format.channelCount);
    [bus setFormat:format error:nil];
}

- (void)setOutputFormat:(AVAudioFormat *)format forBus:(AUAudioUnitBus *)bus {
    NSLog(@"设置输出格式: 采样率=%f, 声道数=%d", format.sampleRate, (int)format.channelCount);
    [bus setFormat:format error:nil];
}

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

- (void)dealloc {
    if (_inputBufferList) {
        if (_inputBufferList->mBuffers[0].mData) {
            free(_inputBufferList->mBuffers[0].mData);
        }
        free(_inputBufferList);
    }
    if (_outputBufferList) {
        if (_outputBufferList->mBuffers[0].mData) {
            free(_outputBufferList->mBuffers[0].mData);
        }
        free(_outputBufferList);
    }
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    // 分配输入和输出缓冲区
    const AVAudioFormat *inputFormat = self.inputBusses[0].format;
    const AVAudioFormat *outputFormat = self.outputBusses[0].format;

    NSLog(@"分配资源 - 输入格式: 采样率=%f, 声道数=%d", inputFormat.sampleRate, (int)inputFormat.channelCount);
    NSLog(@"分配资源 - 输出格式: 采样率=%f, 声道数=%d", outputFormat.sampleRate, (int)outputFormat.channelCount);

    _inputBufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + (sizeof(AudioBuffer) * (inputFormat.channelCount - 1)));
    _outputBufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + (sizeof(AudioBuffer) * (outputFormat.channelCount - 1)));

    if (!_inputBufferList || !_outputBufferList) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                          code:kAudioUnitErr_FailedInitialization
                                      userInfo:nil];
        }
        return NO;
    }

    _inputBufferList->mNumberBuffers = inputFormat.channelCount;
    _outputBufferList->mNumberBuffers = outputFormat.channelCount;

    // 为每个通道分配内存
    for (UInt32 i = 0; i < _inputBufferList->mNumberBuffers; ++i) {
        _inputBufferList->mBuffers[i].mNumberChannels = 1;
        _inputBufferList->mBuffers[i].mDataByteSize = 4096 * sizeof(float);  // 分配足够大的缓冲区
        _inputBufferList->mBuffers[i].mData = malloc(_inputBufferList->mBuffers[i].mDataByteSize);
        if (!_inputBufferList->mBuffers[i].mData) {
            if (outError) {
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                              code:kAudioUnitErr_FailedInitialization
                                          userInfo:nil];
            }
            return NO;
        }
    }

    for (UInt32 i = 0; i < _outputBufferList->mNumberBuffers; ++i) {
        _outputBufferList->mBuffers[i].mNumberChannels = 1;
        _outputBufferList->mBuffers[i].mDataByteSize = 4096 * sizeof(float);  // 分配足够大的缓冲区
        _outputBufferList->mBuffers[i].mData = malloc(_outputBufferList->mBuffers[i].mDataByteSize);
        if (!_outputBufferList->mBuffers[i].mData) {
            if (outError) {
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                              code:kAudioUnitErr_FailedInitialization
                                          userInfo:nil];
            }
            return NO;
        }
    }

    return YES;
}

- (void)deallocateRenderResources {
    if (_inputBufferList) {
        if (_inputBufferList->mBuffers[0].mData) {
            free(_inputBufferList->mBuffers[0].mData);
        }
        free(_inputBufferList);
        _inputBufferList = NULL;
    }
    if (_outputBufferList) {
        if (_outputBufferList->mBuffers[0].mData) {
            free(_outputBufferList->mBuffers[0].mData);
        }
        free(_outputBufferList);
        _outputBufferList = NULL;
    }
    [super deallocateRenderResources];
}

- (AURenderBlock)renderBlock {
    return _renderBlock;
}

@end

@implementation AECAudioNode {
    AVAudioUnit* _audioUnit;
}

static BOOL _isRegistered = NO;

+ (void)registerAudioComponent {
    if (_isRegistered) return;
    
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Effect;
    desc.componentSubType = 'aecu';  // 自定义子类型
    desc.componentManufacturer = 'AECU';
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    [AUAudioUnit registerSubclass:[AECUnit class]
            asComponentDescription:desc
                            name:@"AECUnit"
                        version:0x00010000];
    
    _isRegistered = YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioUnit = nil;
    }
    return self;
}

- (BOOL)initializeWithError:(NSError **)outError {
    if (!_isRegistered) {
        [AECAudioNode registerAudioComponent];
    }
    
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Effect;
    desc.componentSubType = 'aecu';
    desc.componentManufacturer = 'AECU';
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    // 创建 AVAudioUnit
    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    __block NSError *instantiationError = nil;
    
    [AVAudioUnit instantiateWithComponentDescription:desc
                                           options:0
                                 completionHandler:^(AVAudioUnit *unit, NSError *error) {
        if (error) {
            instantiationError = error;
            success = NO;
        } else {
            self->_audioUnit = unit;
            success = YES;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (!success) {
        if (outError) {
            *outError = instantiationError;
        }
        return NO;
    }
    
    return YES;
}

@end 
#import "aec_audio_unit.h"

@implementation AECAudioUnit {
    AudioUnit _audioUnit;
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription {
    self = [super init];
    if (self) {
        // 1. 查找音频组件
        AudioComponent component = AudioComponentFindNext(NULL, &componentDescription);
        if (!component) {
            NSLog(@"找不到指定的音频组件");
            return nil;
        }
        
        // 2. 创建音频单元实例
        OSStatus status = AudioComponentInstanceNew(component, &_audioUnit);
        if (status != noErr) {
            NSLog(@"创建音频单元实例失败: %d", (int)status);
            return nil;
        }
        
        // 3. 初始化音频单元
        status = AudioUnitInitialize(_audioUnit);
        if (status != noErr) {
            NSLog(@"初始化音频单元失败: %d", (int)status);
            AudioComponentInstanceDispose(_audioUnit);
            return nil;
        }
        
        // 4. 设置音频单元属性
        UInt32 enableIO = 1;
        AudioUnitSetProperty(_audioUnit,
                           kAudioOutputUnitProperty_EnableIO,
                           kAudioUnitScope_Output,
                           0,
                           &enableIO,
                           sizeof(enableIO));
    }
    return self;
}

- (void)dealloc {
    if (_audioUnit) {
        AudioUnitUninitialize(_audioUnit);
        AudioComponentInstanceDispose(_audioUnit);
    }
}

@end 
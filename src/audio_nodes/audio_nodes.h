#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface AECUnit : AUAudioUnit

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     error:(NSError **)outError;

- (void)setInputFormat:(AVAudioFormat *)format forBus:(AUAudioUnitBus *)bus;
- (void)setOutputFormat:(AVAudioFormat *)format forBus:(AUAudioUnitBus *)bus;

@end

@interface AECAudioNode : NSObject

@property (nonatomic, strong) AVAudioUnit *audioUnit;

+ (void)registerAudioComponent;
- (instancetype)init;
- (BOOL)initializeWithError:(NSError **)outError;

@end 
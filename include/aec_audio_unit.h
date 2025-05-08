#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@interface AECAudioUnit : AVAudioUnit

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription;

@end

NS_ASSUME_NONNULL_END 
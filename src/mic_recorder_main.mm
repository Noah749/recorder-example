#include "mic_recorder.h"
#include "logger.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>

void TestMicRecorder() {
    @autoreleasepool {
        Logger::info("开始测试麦克风录音");
        
        MicRecorder recorder;
        if (recorder.Start()) {
            Logger::info("测试成功启动，正在录制麦克风音频...");
            // 等待10秒
            [NSThread sleepForTimeInterval:10.0];
            recorder.Stop();
        }
        
        Logger::info("测试完成");
    }
} 
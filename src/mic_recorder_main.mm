#include "mic_recorder.h"
#include "logger.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>

void TestMicRecorder() {
    // @autoreleasepool {
        Logger::info("1. 开始创建 MicRecorder 对象");
        
        MicRecorder recorder;
        Logger::info("2. MicRecorder 对象创建成功");
        
        Logger::info("3. 开始调用 Start() 方法");
        if (recorder.Start()) {
            Logger::info("4. Start() 调用成功，正在录制麦克风音频...");
            // 等待10秒
            [NSThread sleepForTimeInterval:10.0];
            Logger::info("5. 开始调用 Stop() 方法");
            recorder.Stop();
            Logger::info("6. Stop() 调用成功");
        } else {
            Logger::error("4. Start() 调用失败");
        }
        
        Logger::info("7. 测试完成");
    // }
} 
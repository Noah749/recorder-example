#include "av_engine_test.h"
#include "logger.h"

void TestAVAudioEngine() {
    @autoreleasepool {
        Logger::info("开始测试 AVAudioEngine");
        
        AVAudioEngineTest test;
        if (test.Start()) {
            Logger::info("测试成功启动");
            // 等待5秒
            [NSThread sleepForTimeInterval:5.0];
            test.Stop();
        }
        
        Logger::info("测试完成");
    }
} 
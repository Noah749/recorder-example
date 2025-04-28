#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// 最小化 voice processing 测试函数
void TestVoiceProcessingInput() {
    @autoreleasepool {
        // 1. 创建音频引擎
        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *inputNode = [engine inputNode];

        // 2. 开启 voice processing
        NSError *error = nil;
        BOOL success = [inputNode setVoiceProcessingEnabled:YES error:&error];
        if (!success) {
            NSLog(@"开启语音处理失败: %@", error);
            return;
        }

        // 3. 获取新的 format
        AVAudioFormat *format = [inputNode inputFormatForBus:0];

        // 4. 连接 inputNode 到主混音器
        AVAudioMixerNode *mainMixer = [engine mainMixerNode];
        [engine connect:inputNode to:mainMixer format:format];

        // 5. 安装 tap 监听音频数据
        [mainMixer installTapOnBus:0 bufferSize:1024 format:[mainMixer outputFormatForBus:0]
                            block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            NSLog(@"收到音频数据，帧数: %u", buffer.frameLength);
        }];

        // 6. 启动引擎
        if (![engine startAndReturnError:&error]) {
            NSLog(@"音频引擎启动失败: %@", error);
            return;
        }

        NSLog(@"已开启 voice processing，正在监听麦克风输入（按 Ctrl+C 退出）");
        [[NSRunLoop currentRunLoop] run]; // 保持进程运行
    }
}
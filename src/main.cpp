#include <iostream>
#include <string>
#include <filesystem>
#include <chrono>
#include <thread>
#include <sstream>
#include <iomanip>
#include "recorder.h"
#include "logger.h"
#include "mic_recorder.h"
#include <CoreAudio/CoreAudio.h>

// 声明测试函数
void TestMicRecorder();
void TestSystemCaptureRecorder();
void TestAudioEngine();

int main(int argc, char* argv[]) {
    try {
        // 初始化日志系统
        Logger::init("./logs");  // 指定日志目录
        Logger::setLevel(Logger::Level::DEBUG);
        Logger::info("启动本地录音程序");
        
        // 运行麦克风录音测试
        // TestMicRecorder();
        // 运行系统音频捕获测试
        // TestSystemCaptureRecorder();
        // 运行音频引擎 测试
        TestAudioEngine();
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "发生错误: " << e.what() << std::endl;
        return 1;
    }
} 
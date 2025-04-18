#include <iostream>
#include <string>
#include <filesystem>
#include <chrono>
#include <thread>
#include <sstream>
#include <iomanip>
#include "recorder.h"
#include "logger.h"
#include "av_engine_test.h"

// 声明测试函数
void TestAVAudioEngine();

int main(int argc, char* argv[]) {
    // 初始化日志系统
    Logger::init();
    Logger::setLevel(Logger::Level::DEBUG);
    Logger::info("启动本地录音程序");

    // 设置默认输出路径
    std::string outputPath;
    if (argc < 2) {
        // 获取当前工作目录
        std::filesystem::path currentPath = std::filesystem::current_path();
        // 设置默认输出文件名为当前时间戳
        auto now = std::chrono::system_clock::now();
        auto now_time_t = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&now_time_t), "%Y%m%d_%H%M%S");
        outputPath = (currentPath / ("recording_" + ss.str() + ".wav")).string();
        std::cout << "未指定输出路径，将使用默认路径: " << outputPath << std::endl;
    } else {
        outputPath = argv[1];
    }

    AudioRecorder recorder;
    recorder.SetOutputPath(outputPath);

    std::cout << "开始录制 5 秒..." << std::endl;
    if (!recorder.Start()) {
        std::cerr << "启动录音失败" << std::endl;
        return 1;
    }

    // 等待 5 秒
    std::this_thread::sleep_for(std::chrono::seconds(5));

    recorder.Stop();
    std::cout << "录音已停止，文件保存在: " << outputPath << std::endl;

    // 运行 AVAudioEngine 测试
    // TestAVAudioEngine();

    return 0;
} 
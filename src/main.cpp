#include <iostream>
#include <string>
#include "recorder.h"
#include "logger.h"

int main(int argc, char* argv[]) {
    // 初始化日志系统
    Logger::init();
    Logger::setLevel(Logger::Level::DEBUG);
    Logger::info("启动本地录音程序");

    if (argc < 2) {
        std::cout << "使用方法: " << argv[0] << " <输出文件路径>" << std::endl;
        return 1;
    }

    AudioRecorder recorder;
    recorder.SetOutputPath(argv[1]);

    std::cout << "开始录音，按 Enter 键停止..." << std::endl;
    if (!recorder.Start()) {
        std::cerr << "启动录音失败" << std::endl;
        return 1;
    }

    // 等待用户输入
    std::cin.get();

    recorder.Stop();
    std::cout << "录音已停止，文件保存在: " << argv[1] << std::endl;

    return 0;
} 
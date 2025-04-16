#include "logger.h"
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/fmt/fmt.h>
#include <filesystem>
#include <cstdarg>

std::shared_ptr<spdlog::logger> Logger::logger_ = nullptr;
Logger::Level Logger::currentLevel_ = Logger::Level::INFO;
bool Logger::initialized_ = false;

void Logger::init(const std::string& logDir) {
    if (initialized_) {
        return;
    }
    
    try {
        // 创建日志目录
        std::string logDirectory = logDir;
        if (logDirectory.empty()) {
            logDirectory = "./logs";
        }
        
        if (!std::filesystem::exists(logDirectory)) {
            std::filesystem::create_directories(logDirectory);
        }
        
        // 创建控制台和文件日志接收器
        auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        console_sink->set_level(spdlog::level::debug);
        console_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] [%t] %v");
        
        auto file_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
            logDirectory + "/meeting_recorder.log", 
            1024 * 1024 * 5,  // 5MB
            3                  // 保留3个文件
        );
        file_sink->set_level(spdlog::level::trace);
        file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] [%t] %v");
        
        // 创建组合日志记录器
        std::vector<spdlog::sink_ptr> sinks {console_sink, file_sink};
        logger_ = std::make_shared<spdlog::logger>("recorder", sinks.begin(), sinks.end());
        
        // 设置默认日志级别
        logger_->set_level(spdlog::level::info);
        
        // 注册为默认日志记录器
        spdlog::register_logger(logger_);
        spdlog::set_default_logger(logger_);
        
        initialized_ = true;
        
        // 记录初始日志
        logger_->info("日志系统初始化成功");
    }
    catch (const std::exception& ex) {
        fprintf(stderr, "日志系统初始化失败: %s\n", ex.what());
    }
}

void Logger::shutdown() {
    if (initialized_) {
        logger_->info("日志系统关闭");
        spdlog::shutdown();
        initialized_ = false;
    }
}

void Logger::setLevel(Level level) {
    if (!initialized_) {
        init();
    }
    
    currentLevel_ = level;
    
    switch (level) {
        case Level::TRACE:
            logger_->set_level(spdlog::level::trace);
            break;
        case Level::DEBUG:
            logger_->set_level(spdlog::level::debug);
            break;
        case Level::INFO:
            logger_->set_level(spdlog::level::info);
            break;
        case Level::WARN:
            logger_->set_level(spdlog::level::warn);
            break;
        case Level::ERROR:
            logger_->set_level(spdlog::level::err);
            break;
        case Level::CRITICAL:
            logger_->set_level(spdlog::level::critical);
            break;
    }
}

Logger::Level Logger::getLevel() {
    return currentLevel_;
}

// 以下是不同级别日志记录的实现
void Logger::trace(const char* fmt, ...) {
    if (!initialized_) {
        init();
    }
    
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    logger_->trace(buffer);
}

void Logger::debug(const char* fmt, ...) {
    if (!initialized_) {
        init();
    }
    
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    logger_->debug(buffer);
}

void Logger::info(const char* fmt, ...) {
    if (!initialized_) {
        init();
    }
    
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    logger_->info(buffer);
}

void Logger::warn(const char* fmt, ...) {
    if (!initialized_) {
        init();
    }
    
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    logger_->warn(buffer);
}

void Logger::error(const char* fmt, ...) {
    if (!initialized_) {
        init();
    }
    
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    logger_->error(buffer);
}

void Logger::critical(const char* fmt, ...) {
    if (!initialized_) {
        init();
    }
    
    va_list args;
    va_start(args, fmt);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    
    logger_->critical(buffer);
} 
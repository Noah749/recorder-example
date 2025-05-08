#pragma once

#include <string>
#include <memory>

namespace spdlog {
    class logger;
}

class Logger {
public:
    enum class Level {
        TRACE,
        DEBUG,
        INFO,
        WARN,
        ERROR,
        CRITICAL
    };

    static void init(const std::string& logDir = "");
    static void shutdown();
    
    static void setLevel(Level level);
    static Level getLevel();
    
    static void trace(const char* fmt, ...);
    static void debug(const char* fmt, ...);
    static void info(const char* fmt, ...);
    static void warn(const char* fmt, ...);
    static void error(const char* fmt, ...);
    static void critical(const char* fmt, ...);

private:
    static std::shared_ptr<spdlog::logger> logger_;
    static Level currentLevel_;
    static bool initialized_;
}; 
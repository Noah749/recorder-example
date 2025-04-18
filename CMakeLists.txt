cmake_minimum_required(VERSION 3.10)
project(recorder)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置 Objective-C 编译器
set(CMAKE_OBJC_COMPILER "/usr/bin/clang")
set(CMAKE_OBJCXX_COMPILER "/usr/bin/clang++")

# 查找必要的框架
find_library(AVFoundation AVFoundation REQUIRED)
find_library(Foundation Foundation REQUIRED)

# 添加源文件
add_executable(recorder
    src/main.cpp
    src/recorder.cpp
    src/mac_recorder.cpp
    src/logger.cpp
    src/av_engine_test.mm
    src/av_engine_test_main.mm
)

# 设置 Objective-C++ 编译选项
set_target_properties(recorder PROPERTIES
    COMPILE_FLAGS "-x objective-c++ -fobjc-arc"
)

# 添加 spdlog 子目录
add_subdirectory(deps/spdlog-1.12.0)

# 添加头文件目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/deps/spdlog-1.12.0/include
)

# 合并所有链接库到一个调用中
target_link_libraries(recorder PRIVATE
    spdlog::spdlog
    ${AVFoundation}
    ${Foundation}
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AudioUnit"
    "-framework CoreFoundation"
    "-framework CoreServices"
)

# 设置输出目录
set_target_properties(recorder PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 安装目标
install(TARGETS recorder
    RUNTIME DESTINATION bin
) 
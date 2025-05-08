cmake_minimum_required(VERSION 3.10)
project(recorder VERSION 1.0.0)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置 Objective-C 编译器
set(CMAKE_OBJC_COMPILER "/usr/bin/clang")
set(CMAKE_OBJCXX_COMPILER "/usr/bin/clang++")

# 设置 SDK 路径
set(CMAKE_OSX_SYSROOT "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk")
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.2")

# 查找必要的框架
find_library(AVFoundation AVFoundation REQUIRED)
find_library(Foundation Foundation REQUIRED)
find_library(CoreAudio CoreAudio REQUIRED)
find_library(AudioToolbox AudioToolbox REQUIRED)
find_library(AudioUnit AudioUnit REQUIRED)
find_library(CoreFoundation CoreFoundation REQUIRED)
find_library(CoreServices CoreServices REQUIRED)

# 添加源文件
add_executable(recorder
    # src/test_microphone.cpp
    src/main.cpp
    src/recorder.cpp
    src/mac_recorder.cpp
    src/microphone_capture.cpp
    src/ring_buffer.cpp
    src/logger.cpp
    src/mic_recorder.mm
    src/mic_recorder_main.mm
    src/system_capture_recorder_main.mm
    src/audio_device_manager.mm
    src/audio_system_capture.mm
    src/av_engine_taps_main.mm
    src/voice_processing_test.mm
    src/audio_nodes/audio_nodes.mm
)

# 设置 Objective-C++ 编译选项
set_target_properties(recorder PROPERTIES
    COMPILE_FLAGS "-x objective-c++ -fobjc-arc -fmodules"
    OUTPUT_NAME "recorder"
)

# 添加 spdlog 子目录
add_subdirectory(third_party/spdlog-1.12.0)

# 添加头文件目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/include/audio_nodes
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/spdlog-1.12.0/include
)

# 合并所有链接库到一个调用中
target_link_libraries(recorder PRIVATE
    spdlog::spdlog
    ${AVFoundation}
    ${Foundation}
    ${CoreAudio}
    ${AudioToolbox}
    ${AudioUnit}
    ${CoreFoundation}
    ${CoreServices}
)

# 设置输出目录
set_target_properties(recorder PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 安装目标
install(TARGETS recorder
    RUNTIME DESTINATION bin
)

# 添加 entitlements 文件
set_target_properties(recorder PROPERTIES
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/src/recorder.entitlements"
)

# 创建 entitlements 文件
file(WRITE ${CMAKE_CURRENT_SOURCE_DIR}/src/recorder.entitlements
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n"
    "<dict>\n"
    "    <key>com.apple.security.app-sandbox</key>\n"
    "    <true/>\n"
    "    <key>com.apple.security.assets.music.read-write</key>\n"
    "    <true/>\n"
    "    <key>com.apple.security.device.audio-input</key>\n"
    "    <true/>\n"
    "    <key>com.apple.security.files.user-selected.read-write</key>\n"
    "    <true/>\n"
    "</dict>\n"
    "</plist>\n"
) 
cmake_minimum_required(VERSION 3.10)
project(meeting_recorder VERSION 1.0.0)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 添加 spdlog 子目录
add_subdirectory(deps/spdlog-1.12.0)

# 添加源文件
set(SOURCES
    src/recorder.cpp
    src/mac_recorder.cpp
    src/logger.cpp
)

# 添加头文件目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/deps/spdlog-1.12.0/include
)

# 创建可执行文件
add_executable(meeting_recorder 
    ${SOURCES}
    src/main.cpp
)

# 链接 spdlog
target_link_libraries(meeting_recorder PRIVATE spdlog::spdlog)

# 添加 macOS 特定的框架链接
if(APPLE)
    target_link_libraries(meeting_recorder PRIVATE
        "-framework CoreAudio"
        "-framework AudioToolbox"
        "-framework AudioUnit"
        "-framework CoreFoundation"
        "-framework CoreServices"
    )
endif()

# 设置输出目录
set_target_properties(meeting_recorder PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 安装目标
install(TARGETS meeting_recorder
    RUNTIME DESTINATION bin
) 
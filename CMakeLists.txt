cmake_minimum_required(VERSION 3.10)
project(meeting_recorder VERSION 1.0.0)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 添加源文件
set(SOURCES
    src/recorder.cpp
    src/mac_recorder.cpp
    src/logger.cpp
)

# 添加头文件目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# 创建可执行文件
add_executable(meeting_recorder 
    ${SOURCES}
    src/main.cpp
)

# 设置输出目录
set_target_properties(meeting_recorder PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 安装目标
install(TARGETS meeting_recorder
    RUNTIME DESTINATION bin
) 
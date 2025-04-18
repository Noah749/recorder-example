# macOS 麦克风录制实现文档

## 概述

本文档详细说明了会议自动录制工具在 macOS 平台上的麦克风录制实现。我们使用了 Core Audio 框架来实现高质量的音频捕获、处理和存储功能。

## 技术架构

### 核心组件

1. **MacRecorder 类**：用于实现 macOS 平台特定的录音功能
   - 位于 `src/mac_recorder.h` 和 `src/mac_recorder.cpp`
   - 由 `AudioRecorder` 类实例化和管理

2. **Core Audio 组件**：
   - `AudioUnit`：用于获取音频输入数据
   - `ExtAudioFile`：用于将音频数据写入文件
   - `AudioBuffer`：用于缓存音频数据

3. **音频格式**：
   - 采样率：44100Hz (CD 质量)
   - 通道数：1 (单声道)
   - 位深度：16位
   - 文件格式：WAV

## 流程图

### 音频捕获主流程

```
+----------------+     +---------------+     +----------------+
| 应用层初始化    |     | 开始录音       |     | 停止录音       |
| MacRecorder    +---->+ Start()       +---->+ Stop()        |
+----------------+     +-------+-------+     +----------------+
                               |
                               v
         +-------------------------------------------+
         |            音频捕获和处理流程              |
         |                                          |
         |  +------------+     +----------------+   |
         |  | 初始化音频  |     | 打开音频文件    |   |
         |  | 系统       +---->+                |   |
         |  +------------+     +-------+--------+   |
         |                             |            |
         |                             v            |
         |                     +---------------+    |
         |                     | 启动音频单元   |    |
         |                     | AudioUnit     |    |
         |                     +-------+-------+    |
         |                             |            |
         |                             v            |
         |              +-------------------------+ |
         |              | 音频回调循环            | |
         |              | RecordingCallback      | |
         |              |                        | |
         |              | +-------------------+  | |
         |              | | 渲染音频数据       |  | |
         |              | | AudioUnitRender   |  | |
         |              | +--------+----------+  | |
         |              |          |             | |
         |              |          v             | |
         |              | +-------------------+  | |
         |              | | 音频数据处理       |  | |
         |              | | (降噪等)          |  | |
         |              | +--------+----------+  | |
         |              |          |             | |
         |              |          v             | |
         |              | +-------------------+  | |
         |              | | 写入数据到文件     |  | |
         |              | | WriteAudioData    |  | |
         |              | +-------------------+  | |
         |              +-------------------------+ |
         +-------------------------------------------+

```

### 暂停和恢复流程

```
+----------------+     +---------------+     +-----------------+
| 录音中         |     | 暂停录音       |     | 恢复录音         |
| IsRunning()    +---->+ Pause()       +---->+ Resume()        |
+----------------+     +-------+-------+     +-----------------+
                               |                     |
                               v                     v
                    +-------------------+   +-------------------+
                    | 停止音频单元      |   | 重启音频单元       |
                    | AudioOutputUnitStop |  | AudioOutputUnitStart |
                    +-------------------+   +-------------------+
                               |                     |
                               v                     v
                    +-------------------+   +-------------------+
                    | 设置暂停状态      |   | 清除暂停状态       |
                    | paused_ = true    |   | paused_ = false   |
                    +-------------------+   +-------------------+
```

### 异常处理流程

```
+----------------+     +------------------------+
| 操作执行       |     | 异常检测               |
| (任何音频操作)  +---->+ try-catch 块          |
+----------------+     +-----------+------------+
                                  |
                                  v
                     +---------------------------+
                     | 异常处理                  |
                     |                          |
           +---------v----------+  +-----------v------------+
           | 记录错误日志        |  | 资源清理和状态重置      |
           | Logger::error()    |  | (关闭文件、释放内存等)  |
           +--------------------+  +------------------------+
```

## ER 图 (实体关系图)

下面的 ER 图展示了 MacRecorder 与其他组件之间的关系：

```
+---------------+       +-----------------+
| AudioRecorder |       | MacRecorder     |
|               |       |                 |
| +start()      |<>-----| -recorder_      |
| +stop()       |       | -audioUnit_     |
| +pause()      |       | -audioFile_     |
| +resume()     |       | -outputPath_    |
| +isRunning()  |       | -running_       |
+---------------+       | -paused_        |
                        |                 |
                        | +Start()        |
                        | +Stop()         |
                        | +Pause()        |
                        | +Resume()       |
                        | +IsRunning()    |
                        +-----------------+
                               |
                               | 使用
                               v
          +------------------------------------------+
          |                                          |
+---------v----------+  +-------------+  +---------v----------+
| AudioUnit          |  | AudioBuffer |  | ExtAudioFile      |
| (Core Audio)       |  | (内存缓冲区) |  | (文件I/O)         |
|                    |  |             |  |                    |
| +AudioUnitRender() |  | -mData      |  | +Write()          |
| +Start()           |  | -mDataSize  |  | +Create()         |
| +Stop()            |  |             |  | +Dispose()        |
+--------------------+  +-------------+  +--------------------+
```

### 组件关系描述

- **AudioRecorder** (1) ←→ **MacRecorder** (1): 一对一关系，AudioRecorder 作为平台无关的接口，持有 MacRecorder 实例。
- **MacRecorder** (1) → **AudioUnit** (1): 一对一关系，MacRecorder 创建并管理一个 AudioUnit 实例用于音频捕获。
- **MacRecorder** (1) → **AudioBuffer** (多个): 一对多关系，MacRecorder 管理多个音频缓冲区用于数据处理。
- **MacRecorder** (1) → **ExtAudioFile** (1): 一对一关系，MacRecorder 使用一个 ExtAudioFile 实例进行文件操作。

### 数据流向

```
+-------------+     +----------------+     +---------------+     +----------------+
| 麦克风设备   | --> | AudioUnit     | --> | 音频处理缓冲区 | --> | ExtAudioFile   |
| (系统输入)   |     | (音频捕获)     |     | (数据处理)     |     | (WAV文件)      |
+-------------+     +----------------+     +---------------+     +----------------+
```

## 工作流程

### 初始化过程

1. 创建 `MacRecorder` 实例
2. 预分配音频处理缓冲区
3. 设置音频格式参数

### 开始录音 (Start)

1. 初始化音频系统 (InitializeAudio)
   - 创建音频组件描述
   - 查找并创建音频单元 
   - 禁用音频输出，启用音频输入
   - 设置默认输入设备
   - 配置音频回调
   - 设置音频流格式
   - 初始化音频单元

2. 打开音频文件 (OpenAudioFile)
   - 创建文件 URL 
   - 创建 WAV 格式音频文件
   - 设置客户端数据格式

3. 启动音频单元
   - 开始接收音频数据

### 录音过程

1. 音频回调持续接收数据 (RecordingCallback)
2. 音频数据处理 (HandleRecordingCallback)
   - 渲染音频数据
   - 应用降噪处理
   - 写入数据到文件

### 停止录音 (Stop)

1. 停止音频单元
2. 关闭音频文件
3. 清理音频资源

## 降噪处理

我们实现了简单的噪声抑制功能：

1. 将整数音频数据转换为浮点数
2. 应用噪声门限抑制算法
   - 噪声门限值根据用户设置的 0-10 级别动态调整
   - 低于门限的音频信号被置为零
3. 将处理后的浮点数据转换回整数格式

## 异常处理与安全性

1. 内存管理
   - 使用 `calloc` 和 `realloc` 确保初始分配和动态调整
   - 防止内存泄漏的错误处理
   - 析构函数中确保资源释放

2. 线程安全
   - 使用互斥锁保护共享资源
   - 使用 `try_lock` 防止死锁
   - 使用 `std::lock_guard` 确保异常情况下锁的释放

3. 错误处理
   - 详细的错误日志
   - 使用 `try-catch` 块处理关键操作中的异常
   - OSStatus 错误代码检测和处理

## 性能优化

1. 缓冲区预分配
   - 避免实时内存分配导致的性能下降
   - 动态调整缓冲区大小以适应不同的帧数

2. 高效的音频处理
   - 直接在缓冲区上操作，减少数据复制
   - 优化的降噪算法，平衡音质和计算成本

## 注意事项

### 权限要求

在 macOS 上，应用程序需要获取麦克风访问权限才能录制音频。最终的应用程序应：

1. 在 Info.plist 中包含 `NSMicrophoneUsageDescription` 键
2. 首次运行时请求用户授权

### 系统兼容性

- 代码设计兼容 macOS 10.15 及以上版本
- 使用了较新的 Core Audio API，可能需要针对较旧系统进行适配

## 获取使用麦克风的应用信息

目前使用占位符实现，返回"系统默认"。完整实现需要：

1. 监听系统音频设备变化事件
2. 查询活跃的音频应用程序
3. 确定哪个应用程序正在使用麦克风

## 未来改进方向

1. **实现扬声器录制**
   - 添加系统音频捕获功能
   - 开发音频混合算法处理麦克风和扬声器音频

2. **高级音频处理**
   - 实现更复杂的降噪算法
   - 添加自动增益控制
   - 实现音频压缩功能

3. **麦克风使用检测**
   - 完成应用程序检测功能
   - 添加自动启动/停止录制功能

4. **多格式支持**
   - 添加 MP3、AAC 等格式支持
   - 提供不同质量预设

## 代码示例

### 初始化音频系统

```cpp
bool MacRecorder::InitializeAudio() {
    // 创建音频组件描述
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    // 查找音频组件
    AudioComponent component = AudioComponentFindNext(nullptr, &desc);
    
    // 创建音频单元
    AudioComponentInstanceNew(component, &audioUnit_);
    
    // 配置并初始化音频单元
    // ...
}
```

### 音频数据处理

```cpp
OSStatus MacRecorder::HandleRecordingCallback(UInt32 inNumberFrames) {
    // 渲染音频数据
    AudioUnitRender(audioUnit_, &flags, &timeStamp, 1, inNumberFrames, inputBuffer_);
    
    // 应用降噪处理
    if (micNoiseReductionLevel_ > 0) {
        SInt16* samples = static_cast<SInt16*>(inputBuffer_->mBuffers[0].mData);
        // 将数据转换为浮点
        // 应用噪声门限
        // 转换回整数格式
    }
    
    // 写入数据到文件
    WriteAudioDataToFile(inputBuffer_->mBuffers[0].mData, 
                         inputBuffer_->mBuffers[0].mDataByteSize);
}
``` 
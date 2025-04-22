#include "mac_recorder.h"
#include "recorder.h"
#include "logger.h"
#include <algorithm>
#include <cmath>
#include <CoreServices/CoreServices.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

// 定义整数类型
typedef int16_t SInt16;

// 默认音频格式设置
constexpr int kSampleRate = 44100;
constexpr int kChannels = 1;  // 单声道录制麦克风
constexpr int kBitsPerSample = 16;
constexpr int kBytesPerSample = kBitsPerSample / 8;
constexpr int kFramesPerPacket = 1;
constexpr UInt32 kBufferSizeFrames = 1024;

// 构造函数
MacRecorder::MacRecorder(AudioRecorder* recorder)
    : recorder_(recorder),
      running_(false),
      paused_(false),
      audioEngine_(nullptr),
      inputNode_(nullptr),
      systemNode_(nullptr),
      mixerNode_(nullptr),
      audioFormat_(nullptr),
      systemAudioVolume_(1.0f),
      microphoneVolume_(1.0f),
      audioFile_(nullptr),
      fileOpen_(false) {
    
    Logger::debug("MacRecorder: 初始化");
}

// 析构函数
MacRecorder::~MacRecorder() {
    Logger::debug("MacRecorder: 销毁");
    
    if (running_) {
        Stop();
    }
}

// 开始录音
bool MacRecorder::Start() {
    Logger::debug("MacRecorder: 开始录音");
    
    if (running_ && !paused_) {
        Logger::warn("MacRecorder: 已经在录音中");
        return false;
    }
    
    if (paused_) {
        // 如果暂停了，只需要恢复
        Logger::debug("MacRecorder: 恢复已暂停的录音");
        Resume();
        return true;
    }
    
    // 初始化音频系统
    if (!InitializeAudio()) {
        Logger::error("MacRecorder: 初始化音频失败");
        return false;
    }
    
    // 打开音频文件
    if (!OpenAudioFile()) {
        Logger::error("MacRecorder: 打开音频文件失败");
        CleanupAudio();
        return false;
    }
    
    // 启动系统音频捕获
    [systemNode_ startCapture];
    
    // 启动音频引擎
    NSError* error = nil;
    if (![audioEngine_ startAndReturnError:&error]) {
        Logger::error("MacRecorder: 启动音频引擎失败: %s", [[error localizedDescription] UTF8String]);
        CloseAudioFile();
        CleanupAudio();
        return false;
    }
    
    running_ = true;
    paused_ = false;
    Logger::info("MacRecorder: 录音已启动");
    
    // 更新当前使用麦克风的应用
    UpdateCurrentMicrophoneApp();
    
    return true;
}

// 停止录音
void MacRecorder::Stop() {
    Logger::debug("MacRecorder: 停止录音");
    
    if (!running_) {
        Logger::warn("MacRecorder: 未在录音中");
        return;
    }

    // 先标记状态，避免回调中继续处理
    running_ = false;
    paused_ = false;
    
    // 使用try-catch防止异常导致卡住
    try {
        // 停止系统音频捕获
        [systemNode_ stopCapture];
        
        // 停止音频引擎
        if (audioEngine_) {
            [audioEngine_ stop];
            Logger::debug("MacRecorder: 音频引擎已停止");
        }
    }
    catch (const std::exception& e) {
        Logger::error("MacRecorder: 停止音频引擎时发生异常: %s", e.what());
    }
    
    try {
        // 关闭文件
        CloseAudioFile();
        Logger::debug("MacRecorder: 文件已关闭");
    }
    catch (const std::exception& e) {
        Logger::error("MacRecorder: 关闭文件时发生异常: %s", e.what());
    }
    
    try {
        // 清理音频资源
        CleanupAudio();
        Logger::debug("MacRecorder: 音频资源已清理");
    }
    catch (const std::exception& e) {
        Logger::error("MacRecorder: 清理音频资源时发生异常: %s", e.what());
    }
    
    Logger::info("MacRecorder: 录音已停止");
}

// 暂停录音
void MacRecorder::Pause() {
    Logger::debug("MacRecorder: 暂停录音");
    
    if (!running_ || paused_) {
        Logger::warn("MacRecorder: 无法暂停，未在录音中或已暂停");
        return;
    }
    
    std::lock_guard<std::mutex> lock(audioMutex_);
    
    // 暂停音频引擎
    if (audioEngine_) {
        [audioEngine_ pause];
    }
    
    paused_ = true;
    Logger::info("MacRecorder: 录音已暂停");
}

// 恢复录音
void MacRecorder::Resume() {
    Logger::debug("MacRecorder: 恢复录音");
    
    if (!running_ || !paused_) {
        Logger::warn("MacRecorder: 无法恢复，未在录音中或未暂停");
        return;
    }
    
    std::lock_guard<std::mutex> lock(audioMutex_);
    
    // 重新启动音频引擎
    NSError* error = nil;
    if (![audioEngine_ startAndReturnError:&error]) {
        Logger::error("MacRecorder: 恢复录音失败: %s", [[error localizedDescription] UTF8String]);
        return;
    }
    
    paused_ = false;
    Logger::info("MacRecorder: 录音已恢复");
}

// 是否正在录音
bool MacRecorder::IsRunning() const {
    return running_ && !paused_;
}

// 设置输出路径
void MacRecorder::SetOutputPath(const std::string& path) {
    Logger::debug("MacRecorder: 设置输出路径: %s", path.c_str());
    outputPath_ = path;
}

// 获取当前使用麦克风的应用
std::string MacRecorder::GetCurrentMicrophoneApp() {
    if (running_) {
        // 录制中才更新应用状态
        UpdateCurrentMicrophoneApp();
    }
    return currentMicApp_;
}

// 设置系统音频音量
void MacRecorder::SetSystemAudioVolume(float volume) {
    systemAudioVolume_ = std::max(0.0f, std::min(1.0f, volume));
    if (mixerNode_) {
        [mixerNode_ setVolume:systemAudioVolume_];
    }
}

// 设置麦克风音量
void MacRecorder::SetMicrophoneVolume(float volume) {
    microphoneVolume_ = std::max(0.0f, std::min(1.0f, volume));
    if (mixerNode_) {
        [mixerNode_ setVolume:microphoneVolume_];
    }
}

// 初始化音频系统
bool MacRecorder::InitializeAudio() {
    Logger::debug("MacRecorder: 初始化音频系统");
    
    // 创建音频引擎
    audioEngine_ = [[AVAudioEngine alloc] init];
    if (!audioEngine_) {
        Logger::error("MacRecorder: 创建音频引擎失败");
        return false;
    }
    
    // 获取输入节点
    inputNode_ = [audioEngine_ inputNode];
    if (!inputNode_) {
        Logger::error("MacRecorder: 获取麦克风输入节点失败");
        return false;
    }
    
    // 创建系统音频输入节点
    systemNode_ = [MacSystemAudioNode nodeWithEngine:audioEngine_];
    if (!systemNode_) {
        Logger::error("MacRecorder: 创建系统音频输入节点失败");
        return false;
    }
    
    // 创建混合节点
    mixerNode_ = [[AVAudioMixerNode alloc] init];
    if (!mixerNode_) {
        Logger::error("MacRecorder: 创建混合节点失败");
        return false;
    }
    
    // 设置音频格式
    audioFormat_ = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                   sampleRate:kSampleRate
                                                     channels:kChannels
                                                  interleaved:YES];
    if (!audioFormat_) {
        Logger::error("MacRecorder: 设置音频格式失败");
        return false;
    }
    
    // 将节点添加到引擎
    [audioEngine_ attachNode:mixerNode_];
    
    // 连接节点
    [audioEngine_ connect:inputNode_ to:mixerNode_ format:audioFormat_];
    [audioEngine_ connect:systemNode_ to:mixerNode_ format:audioFormat_];
    
    // 设置音量
    [mixerNode_ setVolume:microphoneVolume_];
    [mixerNode_ setVolume:systemAudioVolume_];
    
    // 在混合节点上安装tap来获取混合后的音频
    __block MacRecorder* weakSelf = this;
    [mixerNode_ installTapOnBus:0
                     bufferSize:1024
                         format:audioFormat_
                          block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
        MacRecorder* strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->HandleAudioBuffer(buffer);
        }
    }];
    
    Logger::info("MacRecorder: 音频系统初始化成功");
    return true;
}

// 清理音频资源
void MacRecorder::CleanupAudio() {
    Logger::debug("MacRecorder: 清理音频资源");
    
    if (audioEngine_) {
        [audioEngine_ stop];
        [inputNode_ removeTapOnBus:0];
        [systemNode_ removeTapOnBus:0];
        audioEngine_ = nullptr;
        inputNode_ = nullptr;
        systemNode_ = nullptr;
        mixerNode_ = nullptr;
        audioFormat_ = nullptr;
    }
}

// 打开音频文件
bool MacRecorder::OpenAudioFile() {
    Logger::debug("MacRecorder: 打开音频文件: %s", outputPath_.c_str());
    
    if (outputPath_.empty()) {
        Logger::error("MacRecorder: 输出路径为空");
        return false;
    }
    
    // 确保文件已关闭
    CloseAudioFile();
    
    // 创建文件URL
    NSString* path = [NSString stringWithUTF8String:outputPath_.c_str()];
    NSURL* url = [NSURL fileURLWithPath:path];
    
    // 创建音频文件
    NSError* error = nil;
    audioFile_ = [[AVAudioFile alloc] initForWriting:url
                                           settings:[audioFormat_ settings]
                                              error:&error];
    
    if (!audioFile_ || error) {
        Logger::error("MacRecorder: 创建音频文件失败: %s", [[error localizedDescription] UTF8String]);
        return false;
    }
    
    fileOpen_ = true;
    Logger::info("MacRecorder: 音频文件打开成功");
    return true;
}

// 关闭音频文件
void MacRecorder::CloseAudioFile() {
    Logger::debug("MacRecorder: 关闭音频文件");
    
    if (fileOpen_ && audioFile_) {
        audioFile_ = nullptr;
        fileOpen_ = false;
        Logger::info("MacRecorder: 音频文件已关闭");
    }
}

// 处理音频缓冲区
void MacRecorder::HandleAudioBuffer(AVAudioPCMBuffer* buffer) {
    if (paused_ || !running_ || !fileOpen_) {
        return;
    }
    
    std::lock_guard<std::mutex> lock(audioMutex_);
    
    // 写入数据到文件
    WriteAudioDataToFile(buffer);
}

// 写入音频数据到文件
void MacRecorder::WriteAudioDataToFile(AVAudioPCMBuffer* buffer) {
    if (!fileOpen_ || !audioFile_ || !buffer || buffer.frameLength == 0 || !running_) {
        return;
    }
    
    NSError* error = nil;
    if (![audioFile_ writeFromBuffer:buffer error:&error]) {
        Logger::error("MacRecorder: 写入音频文件失败: %s", [[error localizedDescription] UTF8String]);
    }
}

// 更新当前使用麦克风的应用
void MacRecorder::UpdateCurrentMicrophoneApp() {
    // 在macOS上要获取当前使用麦克风的应用需要使用较复杂的API
    // 这里使用recorder_获取传入的AudioRecorder示例
    if (recorder_) {
        // 在这里使用 recorder_ 变量，避免警告
    }
    
    // 为简化实现，使用"系统默认"作为占位符
    currentMicApp_ = "系统默认";
} 
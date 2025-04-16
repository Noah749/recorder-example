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
      audioUnit_(nullptr),
      micNoiseReductionLevel_(5),
      speakerNoiseReductionLevel_(5),
      audioFile_(nullptr),
      fileOpen_(false),
      inputBuffer_(nullptr) {
    
    Logger::debug("MacRecorder: 初始化");
    
    // 预分配处理缓冲区，避免实时分配
    processingBuffer_.resize(kBufferSizeFrames * kChannels);
    
    // 设置音频格式
    memset(&audioFormat_, 0, sizeof(audioFormat_));
    audioFormat_.mSampleRate = kSampleRate;
    audioFormat_.mFormatID = kAudioFormatLinearPCM;
    audioFormat_.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat_.mFramesPerPacket = kFramesPerPacket;
    audioFormat_.mChannelsPerFrame = kChannels;
    audioFormat_.mBitsPerChannel = kBitsPerSample;
    audioFormat_.mBytesPerPacket = kBytesPerSample * kChannels;
    audioFormat_.mBytesPerFrame = kBytesPerSample * kChannels;
}

// 析构函数
MacRecorder::~MacRecorder() {
    Logger::debug("MacRecorder: 销毁");
    
    if (running_) {
        Stop();
    }
    
    if (inputBuffer_) {
        if (inputBuffer_->mBuffers[0].mData) {
            free(inputBuffer_->mBuffers[0].mData);
            inputBuffer_->mBuffers[0].mData = nullptr;
        }
        free(inputBuffer_);
        inputBuffer_ = nullptr;
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
        return true;  // 如果已经暂停，恢复就认为成功了
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
    
    // 启动音频单元
    OSStatus status = AudioOutputUnitStart(audioUnit_);
    if (status != noErr) {
        Logger::error("MacRecorder: 启动音频单元失败，错误码: %d", status);
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
        // 停止音频单元
        if (audioUnit_) {
            AudioOutputUnitStop(audioUnit_);
            Logger::debug("MacRecorder: 音频单元已停止");
        }
    }
    catch (const std::exception& e) {
        Logger::error("MacRecorder: 停止音频单元时发生异常: %s", e.what());
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
    
    // 暂停音频单元
    if (audioUnit_) {
        AudioOutputUnitStop(audioUnit_);
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
    
    // 重新启动音频单元
    if (audioUnit_) {
        OSStatus status = AudioOutputUnitStart(audioUnit_);
        if (status != noErr) {
            Logger::error("MacRecorder: 恢复录音失败，错误码: %d", status);
            return;
        }
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

// 设置麦克风降噪级别
void MacRecorder::SetMicNoiseReduction(int level) {
    Logger::debug("MacRecorder: 设置麦克风降噪级别: %d", level);
    micNoiseReductionLevel_ = std::max(0, std::min(10, level));
    
    // 如果正在录音，可以应用设置
    if (running_ && audioUnit_) {
        // 实际应用降噪设置的代码
        // 这里将来可以根据不同的level值应用不同强度的降噪
    }
}

// 设置扬声器降噪级别
void MacRecorder::SetSpeakerNoiseReduction(int level) {
    Logger::debug("MacRecorder: 设置扬声器降噪级别: %d", level);
    speakerNoiseReductionLevel_ = std::max(0, std::min(10, level));
    
    // 如果正在录音，可以应用设置
    if (running_ && audioUnit_) {
        // 实际应用降噪设置的代码
    }
}

// 初始化音频系统
bool MacRecorder::InitializeAudio() {
    Logger::debug("MacRecorder: 初始化音频系统");
    
    OSStatus status;
    
    // 创建音频组件描述
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    // 查找音频组件
    AudioComponent component = AudioComponentFindNext(nullptr, &desc);
    if (!component) {
        Logger::error("MacRecorder: 找不到合适的音频组件");
        return false;
    }
    
    // 创建音频单元
    status = AudioComponentInstanceNew(component, &audioUnit_);
    if (status != noErr) {
        Logger::error("MacRecorder: 创建音频单元失败，错误码: %d", status);
        return false;
    }
    
    // 禁用输出
    UInt32 enableIO = 0;
    status = AudioUnitSetProperty(audioUnit_, kAudioOutputUnitProperty_EnableIO,
                                kAudioUnitScope_Output, 0, &enableIO, sizeof(enableIO));
    if (status != noErr) {
        Logger::error("MacRecorder: 禁用音频输出失败，错误码: %d", status);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 启用输入
    enableIO = 1;
    status = AudioUnitSetProperty(audioUnit_, kAudioOutputUnitProperty_EnableIO,
                                kAudioUnitScope_Input, 1, &enableIO, sizeof(enableIO));
    if (status != noErr) {
        Logger::error("MacRecorder: 启用音频输入失败，错误码: %d", status);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 获取默认输入设备
    AudioDeviceID defaultInputDevice;
    UInt32 propertySize = sizeof(defaultInputDevice);
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };
    
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress,
                                       0, nullptr, &propertySize, &defaultInputDevice);
    if (status != noErr) {
        Logger::error("MacRecorder: 获取默认输入设备失败，错误码: %d", status);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 设置音频单元使用默认输入设备
    status = AudioUnitSetProperty(audioUnit_, kAudioOutputUnitProperty_CurrentDevice,
                                kAudioUnitScope_Global, 0, &defaultInputDevice, sizeof(defaultInputDevice));
    if (status != noErr) {
        Logger::error("MacRecorder: 设置音频单元输入设备失败，错误码: %d", status);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 设置输入回调
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = MacRecorder::RecordingCallback;
    callbackStruct.inputProcRefCon = this;
    status = AudioUnitSetProperty(audioUnit_, kAudioOutputUnitProperty_SetInputCallback,
                                kAudioUnitScope_Global, 0, &callbackStruct, sizeof(callbackStruct));
    if (status != noErr) {
        Logger::error("MacRecorder: 设置音频输入回调失败，错误码: %d", status);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 设置音频流格式
    status = AudioUnitSetProperty(audioUnit_, kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Output, 1, &audioFormat_, sizeof(audioFormat_));
    if (status != noErr) {
        Logger::error("MacRecorder: 设置音频流格式失败，错误码: %d", status);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 创建音频缓冲区
    UInt32 bufferSizeBytes = kBufferSizeFrames * audioFormat_.mBytesPerFrame;
    inputBuffer_ = static_cast<AudioBufferList*>(calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer)));
    if (!inputBuffer_) {
        Logger::error("MacRecorder: 分配音频缓冲区失败");
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    inputBuffer_->mNumberBuffers = 1;
    inputBuffer_->mBuffers[0].mNumberChannels = audioFormat_.mChannelsPerFrame;
    inputBuffer_->mBuffers[0].mDataByteSize = bufferSizeBytes;
    inputBuffer_->mBuffers[0].mData = calloc(1, bufferSizeBytes);
    if (!inputBuffer_->mBuffers[0].mData) {
        Logger::error("MacRecorder: 分配音频数据缓冲区失败");
        free(inputBuffer_);
        inputBuffer_ = nullptr;
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    // 初始化音频单元
    status = AudioUnitInitialize(audioUnit_);
    if (status != noErr) {
        Logger::error("MacRecorder: 初始化音频单元失败，错误码: %d", status);
        if (inputBuffer_->mBuffers[0].mData) {
            free(inputBuffer_->mBuffers[0].mData);
        }
        free(inputBuffer_);
        inputBuffer_ = nullptr;
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }
    
    Logger::info("MacRecorder: 音频系统初始化成功");
    return true;
}

// 清理音频资源
void MacRecorder::CleanupAudio() {
    Logger::debug("MacRecorder: 清理音频资源");
    
    if (audioUnit_) {
        OSStatus status = AudioUnitUninitialize(audioUnit_);
        if (status != noErr) {
            Logger::warn("MacRecorder: 音频单元反初始化失败，错误码: %d", status);
        }
        
        status = AudioComponentInstanceDispose(audioUnit_);
        if (status != noErr) {
            Logger::warn("MacRecorder: 释放音频单元失败，错误码: %d", status);
        }
        
        audioUnit_ = nullptr;
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
    
    // 创建CFURL
    CFStringRef cfPath = CFStringCreateWithCString(kCFAllocatorDefault, outputPath_.c_str(), kCFStringEncodingUTF8);
    if (!cfPath) {
        Logger::error("MacRecorder: 创建CFString失败");
        return false;
    }
    
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfPath, kCFURLPOSIXPathStyle, false);
    CFRelease(cfPath);
    
    if (!url) {
        Logger::error("MacRecorder: 创建CFURL失败");
        return false;
    }
    
    // 创建音频文件
    OSStatus status = ExtAudioFileCreateWithURL(url, kAudioFileWAVEType, &audioFormat_, nullptr, 
                                              kAudioFileFlags_EraseFile, &audioFile_);
    CFRelease(url);
    
    if (status != noErr) {
        Logger::error("MacRecorder: 创建音频文件失败，错误码: %d", status);
        return false;
    }
    
    // 设置客户端数据格式（与写入的格式相同）
    status = ExtAudioFileSetProperty(audioFile_, kExtAudioFileProperty_ClientDataFormat, 
                                   sizeof(audioFormat_), &audioFormat_);
    if (status != noErr) {
        Logger::error("MacRecorder: 设置音频文件客户端格式失败，错误码: %d", status);
        ExtAudioFileDispose(audioFile_);
        audioFile_ = nullptr;
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
        OSStatus status = ExtAudioFileDispose(audioFile_);
        if (status != noErr) {
            Logger::warn("MacRecorder: 关闭音频文件失败，错误码: %d", status);
        }
        audioFile_ = nullptr;
        fileOpen_ = false;
        Logger::info("MacRecorder: 音频文件已关闭");
    }
}

// 写入音频数据到文件
void MacRecorder::WriteAudioDataToFile(const void* data, UInt32 numBytes) {
    if (!fileOpen_ || !audioFile_ || !data || numBytes == 0 || !running_) {
        return;
    }
    
    // 创建音频缓冲区
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = const_cast<void*>(data);
    bufferList.mBuffers[0].mDataByteSize = numBytes;
    bufferList.mBuffers[0].mNumberChannels = audioFormat_.mChannelsPerFrame;
    
    // 计算帧数
    UInt32 numFrames = numBytes / audioFormat_.mBytesPerFrame;
    
    // 写入文件
    OSStatus status = ExtAudioFileWrite(audioFile_, numFrames, &bufferList);
    if (status != noErr) {
        Logger::error("MacRecorder: 写入音频文件失败，错误码: %d", status);
    }
}

// 静态录音回调
OSStatus MacRecorder::RecordingCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
                                       const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                       UInt32 inNumberFrames, AudioBufferList* ioData) {
    MacRecorder* recorder = static_cast<MacRecorder*>(inRefCon);
    if (recorder) {
        return recorder->HandleRecordingCallback(inNumberFrames);
    }
    return noErr;
}

// 处理录音回调
OSStatus MacRecorder::HandleRecordingCallback(UInt32 inNumberFrames) {
    // 如果暂停、停止或文件关闭，则不处理
    if (paused_ || !running_ || !fileOpen_) {
        return noErr;
    }
    
    // 尝试锁定互斥锁，如果失败（可能在Stop方法中），则返回
    if (!audioMutex_.try_lock()) {
        return noErr;
    }
    
    // 使用智能指针确保锁会被释放
    std::lock_guard<std::mutex> lock(audioMutex_, std::adopt_lock);
    
    // 检查AudioUnit是否有效
    if (!audioUnit_) {
        return noErr;
    }
    
    // 渲染音频数据
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp timeStamp;
    memset(&timeStamp, 0, sizeof(timeStamp));
    timeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    
    // 确保缓冲区大小足够
    UInt32 expectedBytes = inNumberFrames * audioFormat_.mBytesPerFrame;
    if (inputBuffer_->mBuffers[0].mDataByteSize < expectedBytes) {
        void* newBuffer = realloc(inputBuffer_->mBuffers[0].mData, expectedBytes);
        if (!newBuffer) {
            Logger::error("MacRecorder: 重新分配音频缓冲区失败");
            return kAudio_MemFullError;
        }
        inputBuffer_->mBuffers[0].mData = newBuffer;
        inputBuffer_->mBuffers[0].mDataByteSize = expectedBytes;
    }
    
    // 从音频单元获取音频数据
    OSStatus status = AudioUnitRender(audioUnit_, &flags, &timeStamp, 1, inNumberFrames, inputBuffer_);
    if (status != noErr) {
        Logger::error("MacRecorder: 渲染音频数据失败，错误码: %d", status);
        return status;
    }
    
    // 如果需要降噪处理
    if (micNoiseReductionLevel_ > 0) {
        // 转换为浮点格式以便处理
        SInt16* samples = static_cast<SInt16*>(inputBuffer_->mBuffers[0].mData);
        const float scale = 1.0f / 32768.0f;
        
        // 确保处理缓冲区足够大
        if (processingBuffer_.size() < inNumberFrames) {
            processingBuffer_.resize(inNumberFrames);
        }
        
        // 将数据转换为浮点并应用简单的降噪
        for (UInt32 i = 0; i < inNumberFrames; ++i) {
            processingBuffer_[i] = samples[i] * scale;
        }
        
        // 简单的阈值噪声门控 (根据降噪级别调整阈值)
        float threshold = 0.005f * micNoiseReductionLevel_ / 10.0f;
        for (UInt32 i = 0; i < inNumberFrames; ++i) {
            if (std::abs(processingBuffer_[i]) < threshold) {
                processingBuffer_[i] = 0.0f;
            }
        }
        
        // 转换回整数格式
        for (UInt32 i = 0; i < inNumberFrames; ++i) {
            samples[i] = static_cast<SInt16>(processingBuffer_[i] * 32768.0f);
        }
    }
    
    // 写入数据到文件
    WriteAudioDataToFile(inputBuffer_->mBuffers[0].mData, inputBuffer_->mBuffers[0].mDataByteSize);
    
    return noErr;
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
    
    // 实际实现可以使用Core Audio API或其他macOS API来检测
    // 例如，可以使用 kAudioDevicePropertyDeviceHasChanged 监听麦克风使用状态的变化
} 
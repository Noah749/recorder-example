#include "recorder.h"
#include "logger.h"
#include "mac_recorder.h"

// 基础实现，后续会根据平台进行具体功能实现
AudioRecorder::AudioRecorder() 
    : isRecording_(false), 
      isPaused_(false), 
      micNoiseReductionLevel_(5), 
      speakerNoiseReductionLevel_(5),
      platformImpl_(nullptr) {
    // 初始化日志系统
    Logger::init();
    Logger::info("AudioRecorder 初始化");
    
    // 创建平台特定实现
#ifdef __APPLE__
    platformImpl_ = new MacRecorder(this);
    Logger::info("使用 macOS 录音实现");
#else
    Logger::warn("当前平台尚未实现录音功能");
#endif
}

AudioRecorder::~AudioRecorder() {
    Logger::info("AudioRecorder 销毁中");
    if (isRecording_) {
        Stop();
    }
    
    // 清理平台特定资源
    if (platformImpl_) {
#ifdef __APPLE__
        delete platformImpl_;
#endif
        platformImpl_ = nullptr;
    }
    
    Logger::shutdown();
}

bool AudioRecorder::Start() {
    Logger::info("开始录制请求");
    if (isRecording_ && !isPaused_) {
        Logger::warn("已经在录制中，忽略开始请求");
        return false;
    }
    
    // 使用平台实现
    bool success = false;
    if (platformImpl_) {
#ifdef __APPLE__
        success = platformImpl_->Start();
#endif
    } else {
        Logger::error("平台实现为空，无法开始录制");
        return false;
    }
    
    if (success) {
        isRecording_ = true;
        isPaused_ = false;
        Logger::info("录制状态设置为: 录制中");
    } else {
        Logger::error("平台录制启动失败");
    }
    
    return success;
}

void AudioRecorder::Stop() {
    Logger::info("停止录制请求");
    if (!isRecording_) {
        Logger::warn("未在录制中，忽略停止请求");
        return;
    }
    
    // 使用平台实现
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->Stop();
#endif
    }
    
    isRecording_ = false;
    isPaused_ = false;
    Logger::info("录制状态设置为: 已停止");
}

void AudioRecorder::Pause() {
    Logger::info("暂停录制请求");
    if (!isRecording_ || isPaused_) {
        Logger::warn("未在录制中或已暂停，忽略暂停请求");
        return;
    }
    
    // 使用平台实现
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->Pause();
#endif
    }
    
    isPaused_ = true;
    Logger::info("录制状态设置为: 已暂停");
}

void AudioRecorder::Resume() {
    Logger::info("恢复录制请求");
    if (!isRecording_ || !isPaused_) {
        Logger::warn("未在录制中或未暂停，忽略恢复请求");
        return;
    }
    
    // 使用平台实现
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->Resume();
#endif
    }
    
    isPaused_ = false;
    Logger::info("录制状态设置为: 录制中(恢复)");
}

bool AudioRecorder::IsRecording() const {
    bool status = isRecording_ && !isPaused_;
    Logger::debug("查询录制状态: %s", status ? "录制中" : "未录制");
    return status;
}

void AudioRecorder::SetOutputPath(const std::string& path) {
    Logger::info("设置输出路径: %s", path.c_str());
    outputPath_ = path;
    
    // 设置平台实现的输出路径
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->SetOutputPath(path);
#endif
    }
}

std::string AudioRecorder::GetCurrentMicrophoneApp() {
    Logger::info("获取当前占用麦克风的应用");
    
    if (platformImpl_) {
#ifdef __APPLE__
        return platformImpl_->GetCurrentMicrophoneApp();
#endif
    }
    
    return "Unknown Application";
}

void AudioRecorder::SetMicNoiseReduction(int level) {
    if (level < 0) level = 0;
    if (level > 10) level = 10;
    
    Logger::info("设置麦克风降噪级别: %d", level);
    micNoiseReductionLevel_ = level;
    
    // 设置平台实现的降噪级别
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->SetMicNoiseReduction(level);
#endif
    }
}

void AudioRecorder::SetSpeakerNoiseReduction(int level) {
    if (level < 0) level = 0;
    if (level > 10) level = 10;
    
    Logger::info("设置扬声器降噪级别: %d", level);
    speakerNoiseReductionLevel_ = level;
    
    // 设置平台实现的降噪级别
    if (platformImpl_) {
#ifdef __APPLE__
        platformImpl_->SetSpeakerNoiseReduction(level);
#endif
    }
} 
#include "microphone_capture.h"
#include "ring_buffer.h"
#include <AudioToolbox/AudioToolbox.h>
#include <iostream>
#include <thread>
#include <chrono>
#include <vector>

int main() {
    // 创建麦克风捕获实例
    MicrophoneCapture mic;
    if (!mic.Start()) {
        std::cerr << "无法启动麦克风捕获" << std::endl;
        return 1;
    }
    
    // 创建输出文件
    CFURLRef outputURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                      CFSTR("output.wav"),
                                                      kCFURLPOSIXPathStyle,
                                                      false);
    
    // 设置音频格式
    AudioStreamBasicDescription outputFormat;
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate = 44100;
    outputFormat.mFormatID = kAudioFormatLinearPCM;
    outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    outputFormat.mBitsPerChannel = 32;
    outputFormat.mChannelsPerFrame = 1;
    outputFormat.mFramesPerPacket = 1;
    outputFormat.mBytesPerFrame = outputFormat.mChannelsPerFrame * outputFormat.mBitsPerChannel / 8;
    outputFormat.mBytesPerPacket = outputFormat.mBytesPerFrame;
    
    // 创建音频文件
    ExtAudioFileRef audioFile;
    OSStatus status = ExtAudioFileCreateWithURL(outputURL,
                                               kAudioFileWAVEType,
                                               &outputFormat,
                                               NULL,
                                               kAudioFileFlags_EraseFile,
                                               &audioFile);
    CFRelease(outputURL);
    
    if (status != noErr) {
        std::cerr << "无法创建音频文件: " << status << std::endl;
        mic.Stop();
        return 1;
    }
    
    // 开始录制
    std::cout << "开始录制... (5秒)" << std::endl;
    
    const size_t bufferSize = 1024;
    std::vector<float> buffer(bufferSize);
    UInt32 totalFrames = 0;
    
    auto startTime = std::chrono::steady_clock::now();
    while (std::chrono::duration_cast<std::chrono::seconds>(
           std::chrono::steady_clock::now() - startTime).count() < 5) {
        
        if (mic.ReadAudioData(buffer, bufferSize)) {
            AudioBufferList bufferList;
            bufferList.mNumberBuffers = 1;
            bufferList.mBuffers[0].mNumberChannels = outputFormat.mChannelsPerFrame;
            bufferList.mBuffers[0].mDataByteSize = bufferSize * sizeof(float);
            bufferList.mBuffers[0].mData = buffer.data();
            
            UInt32 frameCount = bufferSize;
            status = ExtAudioFileWrite(audioFile, frameCount, &bufferList);
            if (status != noErr) {
                std::cerr << "写入音频数据失败: " << status << std::endl;
                break;
            }
            
            totalFrames += frameCount;
            std::cout << "已写入 " << totalFrames << " 帧" << std::endl;
        }
        
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    
    // 关闭文件
    status = ExtAudioFileDispose(audioFile);
    if (status != noErr) {
        std::cerr << "关闭音频文件失败: " << status << std::endl;
    }
    
    mic.Stop();
    
    std::cout << "录制完成，共录制 " << totalFrames << " 帧音频数据" << std::endl;
    return 0;
} 
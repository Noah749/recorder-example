const { Recorder } = require('./build/Release/recorder');
const fs = require('fs');
const path = require('path');

// 创建录音器实例
const recorder = new Recorder();

// 创建聚合设备
const deviceID = recorder.createAggregateDevice('Plaud.ai.AggregateDevice');
console.log('聚合设备创建成功，ID:', deviceID);

// 初始化系统音频捕获
const initResult = recorder.initSystemCapture();
console.log('系统音频捕获初始化:', initResult);

// 获取音频格式
const audioFormat = recorder.getAudioFormat();
console.log('音频格式:', {
    采样率: audioFormat.sampleRate + ' Hz',
    声道数: audioFormat.channels,
    位深度: audioFormat.bitsPerChannel + ' bits',
    格式ID: audioFormat.formatID,
    格式标志: audioFormat.formatFlags,
    每帧字节数: audioFormat.bytesPerFrame,
    每包帧数: audioFormat.framesPerPacket,
    每包字节数: audioFormat.bytesPerPacket
});

// 存储所有音频数据
const allAudioData = [];
let isRecording = false;

// 设置音频数据回调
recorder.setSystemCaptureCallback((audioData) => {
    if (isRecording) {
        if (audioData.timestamp > 10) {
            // 停止录音
            isRecording = false;
        }

        // 存储音频数据
        allAudioData.push({
            frames: audioData.numberFrames,
            channels: audioData.numberChannels,
            timestamp: audioData.timestamp,
            data: new Float32Array(audioData.data)
        });
        
        // 计算平均音量
        const samples = new Float32Array(audioData.data);
        const volume = samples.reduce((sum, sample) => sum + Math.abs(sample), 0) / samples.length;
        console.log(`时间戳: ${audioData.timestamp.toFixed(3)}s, 平均音量: ${volume.toFixed(4)}`);

        if (!isRecording) {
            recorder.stopSystemCapture();
            console.log('系统音频捕获已停止');

            // 保存为 WAV 文件
            const wavPath = path.join(__dirname, 'output.wav');
            saveAsWav(allAudioData, wavPath);
            console.log('WAV 文件已保存到:', wavPath);

            // 释放聚合设备
            recorder.releaseAggregateDevice();
            console.log('聚合设备已释放');
            // 强制退出进程
            process.exit(0);
        }
    }
});

// 开始系统音频捕获
const startResult = recorder.startSystemCapture();
console.log('开始系统音频捕获:', startResult);
isRecording = true;

// 处理进程退出
process.on('SIGINT', () => {
    console.log('\n正在清理资源...');
    isRecording = false;
    recorder.stopSystemCapture();
    recorder.releaseAggregateDevice();
    process.exit(0);
});

// 保存为 WAV 文件的函数
function saveAsWav(audioData, filePath) {
    const { sampleRate, channels, bitsPerChannel } = audioFormat;
    
    // 计算总数据长度
    const totalSamples = audioData.reduce((sum, frame) => sum + frame.data.length, 0);
    const dataSize = totalSamples * (bitsPerChannel / 8);
    const headerSize = 44;
    const fileSize = headerSize + dataSize;
    
    // 创建缓冲区
    const buffer = Buffer.alloc(fileSize);
    
    // 写入 WAV 文件头
    // "RIFF" 标识
    buffer.write('RIFF', 0);
    // 文件大小
    buffer.writeUInt32LE(fileSize - 8, 4);
    // "WAVE" 标识
    buffer.write('WAVE', 8);
    // "fmt " 标识
    buffer.write('fmt ', 12);
    // fmt 块大小
    buffer.writeUInt32LE(16, 16);
    // 音频格式 (3 表示 IEEE 浮点)
    buffer.writeUInt16LE(3, 20);
    // 通道数
    buffer.writeUInt16LE(channels, 22);
    // 采样率
    buffer.writeUInt32LE(sampleRate, 24);
    // 字节率
    buffer.writeUInt32LE(sampleRate * channels * (bitsPerChannel / 8), 28);
    // 块对齐
    buffer.writeUInt16LE(channels * (bitsPerChannel / 8), 32);
    // 位深度
    buffer.writeUInt16LE(bitsPerChannel, 34);
    // "data" 标识
    buffer.write('data', 36);
    // 数据大小
    buffer.writeUInt32LE(dataSize, 40);
    
    // 写入音频数据
    let offset = 44;
    for (const frame of audioData) {
        for (let i = 0; i < frame.data.length; i++) {
            // 直接写入 float32 数据
            buffer.writeFloatLE(frame.data[i], offset);
            offset += 4;
        }
    }
    
    // 写入文件
    fs.writeFileSync(filePath, buffer);
} 
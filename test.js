'use strict';

const recorder = require('./');

console.log('测试会议录制模块');

// 创建录制实例
const recorderInstance = new recorder.Recorder();

// 设置输出路径
recorderInstance.setOutputPath('./recording.wav');

// 设置降噪级别
recorderInstance.setMicNoiseReduction(7);
recorderInstance.setSpeakerNoiseReduction(7);

// 显示当前使用麦克风的应用
console.log('当前使用麦克风的应用:', recorderInstance.getCurrentMicrophoneApp());

// 开始录制
const success = recorderInstance.start();
console.log('开始录制:', success ? '成功' : '失败');

// 显示录制状态
console.log('正在录制:', recorderInstance.isRecording());

// 等待 5 秒后暂停
setTimeout(() => {
    recorderInstance.pause();
    
    // 等待 2 秒后恢复
    setTimeout(() => {
        recorderInstance.resume();
        
        // 再等待 3 秒后停止
        setTimeout(() => {
            recorderInstance.stop();
            console.log('测试完成');
        }, 3000);
    }, 2000);
}, 5000);

console.log('录制测试启动中...'); 
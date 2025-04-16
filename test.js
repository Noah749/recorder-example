'use strict';

// 引入会议录制模块 (使用相对路径)
const recorder = require('./');

console.log('测试 macOS 麦克风录制功能');

// 创建录制实例
console.log('创建录制实例...');
const recorderInstance = new recorder.Recorder();

// 设置输出路径
console.log('设置输出路径...');
recorderInstance.setOutputPath('./test-recording.wav');

// 设置降噪级别
console.log('设置降噪级别...');
recorderInstance.setMicNoiseReduction(5);
recorderInstance.setSpeakerNoiseReduction(5);

// 获取使用麦克风的应用
console.log('获取当前使用麦克风的应用...');
const app = recorderInstance.getCurrentMicrophoneApp();
console.log('当前使用麦克风的应用:', app);

// 测试录制功能
console.log('开始录制...');
const success = recorderInstance.start();
console.log('开始录制:', success ? '成功' : '失败');
console.log('录制状态:', recorderInstance.isRecording());

// 5秒后停止录制
console.log('将在5秒后停止录制...');
setTimeout(() => {
  console.log('停止录制');
  recorderInstance.stop();
  console.log('录制状态:', recorderInstance.isRecording());
  console.log('测试完成，录音文件保存在: ./test-recording.wav');
}, 5000); 
'use strict';

// 引入已安装的会议录制模块
const recorder = require('meeting-recorder');

console.log('测试已安装的会议录制模块');

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
console.log('测试录制功能...');
console.log('开始录制:', recorderInstance.start());
console.log('录制状态:', recorderInstance.isRecording());

// 等待 1 秒后停止
setTimeout(() => {
  console.log('停止录制');
  recorderInstance.stop();
  console.log('录制状态:', recorderInstance.isRecording());
  console.log('测试完成！模块安装成功');
}, 1000); 
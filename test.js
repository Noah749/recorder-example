'use strict';

console.log('测试优化后的会议录制模块');

// 引入会议录制模块
const recorder = require('meeting-recorder');

console.log('模块加载成功!');

// 创建录制实例
const recorderInstance = new recorder.Recorder();
console.log('创建录制实例成功');

// 测试一些基本功能
recorderInstance.setOutputPath('./test-recording.wav');
recorderInstance.setMicNoiseReduction(5);
console.log('当前使用麦克风的应用:', recorderInstance.getCurrentMicrophoneApp());
console.log('开始录制:', recorderInstance.start());
console.log('录制状态:', recorderInstance.isRecording());

// 停止录制
setTimeout(() => {
  recorderInstance.stop();
  console.log('测试完成，模块安装成功！');
}, 1000); 
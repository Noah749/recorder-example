'use strict';

// 引入录制模块 (使用相对路径)
const recorder = require('./');

console.log('开始测试...');

// try {
//     // 测试麦克风录制
//     console.log('开始测试麦克风录音...');
//     console.log('调用 testMicRecorder() 前');
//     recorder.testMicRecorder();
//     console.log('调用 testMicRecorder() 后');
// } catch (error) {
//     console.error('麦克风录音测试失败:', error);
//     console.error('错误堆栈:', error.stack);
// }

// 测试系统音频捕获
try {
    console.log('开始测试系统音频捕获...');
    recorder.testSystemCaptureRecorder();
    console.log('系统音频捕获测试完成');
} catch (error) {
    console.error('系统音频捕获测试失败:', error);
}

// 测试音频引擎
// try {
//     console.log('开始测试音频引擎...');
//     recorder.testAudioEngine();
//     console.log('音频引擎测试完成');
// } catch (error) {
//     console.error('音频引擎测试失败:', error);
// }

console.log('测试结束');
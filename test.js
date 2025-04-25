'use strict';

const { Recorder } = require('./build/Release/recorder');

async function testRecorder() {
    console.log('开始测试录音功能...');
    
    const recorder = new Recorder();
    
    try {
        // 设置输出路径
        recorder.setOutputPath('./test_output.wav');
        
        // 开始录音
        console.log('开始录音...');
        const success = recorder.start();
        if (!success) {
            throw new Error('启动录音失败');
        }
        
        // 获取当前使用麦克风的应用
        console.log('当前使用麦克风的应用:', recorder.getCurrentMicrophoneApp());
        
        // 等待5秒
        await new Promise(resolve => setTimeout(resolve, 5000));
        
        // 暂停录音
        console.log('暂停录音...');
        recorder.pause();
        
        // 等待2秒
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // 恢复录音
        console.log('恢复录音...');
        recorder.resume();
        
        // 等待3秒
        await new Promise(resolve => setTimeout(resolve, 3000));
        
        // 停止录音
        console.log('停止录音...');
        recorder.stop();
        
        // 检查录音状态
        console.log('录音状态:', recorder.isRecording() ? '正在录音' : '已停止');
        
        console.log('测试完成');
    } catch (error) {
        console.error('测试过程中发生错误:', error);
    }
}

testRecorder().catch(console.error);
# 会议自动录制工具

这是一个跨平台（macOS、Windows）的会议自动录制工具，作为 Node.js 原生模块提供。

## 功能特点

1. 麦克风被占用时自动录制，麦克风退出时自动停止，显示占用麦克风的应用名
2. 录制系统音频与麦克风的声音，并混合输出为一个音频文件，解决回声问题
3. 支持暂停、恢复录制
4. 支持在录制过程中插拔耳机，确保输出文件中仍包含麦克风和扬声器/耳机的声音
5. 支持麦克风噪声消除
6. 支持扬声器噪声消除
7. 支持在录制过程中修改噪声消除配置

## 安装依赖

本项目需要安装以下依赖：

```bash
# 安装 Node.js 依赖
npm install

# macOS 需要的依赖
# 已经在系统中提供

# Windows 需要的依赖
# 需要安装 Windows SDK
```

## 构建

```bash
# 使用 node-gyp 构建原生模块
npm install
```

## 打包和发布

```bash
# 构建和打包
npm run pack

# 打包后的文件在 dist 目录下
# 预编译的二进制文件在 prebuilds 目录下
```

## 使用示例

```javascript
const recorder = require('meeting-recorder');

// 创建录制实例
const recorderInstance = new recorder.Recorder();

// 设置输出路径
recorderInstance.setOutputPath('./recording.wav');

// 设置降噪级别 (0-10)
recorderInstance.setMicNoiseReduction(7);
recorderInstance.setSpeakerNoiseReduction(7);

// 显示当前使用麦克风的应用
console.log('当前使用麦克风的应用:', recorderInstance.getCurrentMicrophoneApp());

// 开始录制
recorderInstance.start();

// 暂停录制
recorderInstance.pause();

// 恢复录制
recorderInstance.resume();

// 停止录制
recorderInstance.stop();

// 检查是否正在录制
console.log('正在录制:', recorderInstance.isRecording());
```

## API 文档

### Recorder 类

#### 构造函数

- `new Recorder()` - 创建新的录制实例

#### 方法

- `start()` - 开始录制，返回布尔值表示是否成功
- `stop()` - 停止录制
- `pause()` - 暂停录制
- `resume()` - 恢复录制
- `isRecording()` - 返回布尔值表示是否正在录制
- `setOutputPath(path)` - 设置录制文件的输出路径
- `getCurrentMicrophoneApp()` - 获取当前占用麦克风的应用名称
- `setMicNoiseReduction(level)` - 设置麦克风降噪级别，0-10
- `setSpeakerNoiseReduction(level)` - 设置扬声器降噪级别，0-10

## 开发

本项目使用 node-addon-api 进行开发，提供了跨平台的 C++ 代码库。

```bash
# 运行测试
npm test

# 下载依赖库
npm run download-deps

# 构建项目
npm run build
```
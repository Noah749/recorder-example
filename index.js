'use strict';

const path = require('path');
const nodeGypBuild = require('node-gyp-build');

// 尝试加载预编译的二进制文件
let binding;
try {
  binding = nodeGypBuild(path.join(__dirname));
} catch (e) {
  console.error('无法加载会议录制模块:', e.message);
  console.error('此模块依赖预编译的二进制文件，确保安装了正确的版本。');
  throw new Error(`会议录制模块加载失败: ${e.message}`);
}

module.exports = binding; 
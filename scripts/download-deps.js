'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

const DEPS_DIR = path.join(__dirname, '..', 'deps');
const SPDLOG_VERSION = '1.12.0';
const SPDLOG_URL = `https://github.com/gabime/spdlog/archive/v${SPDLOG_VERSION}.tar.gz`;
const SPDLOG_DIR = path.join(DEPS_DIR, `spdlog-${SPDLOG_VERSION}`);
const SPDLOG_INCLUDE_DIR = path.join(DEPS_DIR, 'spdlog', 'include');

// 创建依赖目录
if (!fs.existsSync(DEPS_DIR)) {
  fs.mkdirSync(DEPS_DIR, { recursive: true });
}

// 下载并解压 spdlog
function downloadAndExtractSpdlog() {
  console.log(`下载 spdlog v${SPDLOG_VERSION}...`);
  
  if (fs.existsSync(SPDLOG_DIR)) {
    console.log('spdlog 已存在，跳过下载');
    return;
  }
  
  const tarballPath = path.join(DEPS_DIR, `spdlog-${SPDLOG_VERSION}.tar.gz`);
  
  // 下载 tarball
  const file = fs.createWriteStream(tarballPath);
  https.get(SPDLOG_URL, (response) => {
    response.pipe(file);
    file.on('finish', () => {
      file.close(() => {
        console.log('下载完成，开始解压...');
        
        // 解压 tarball
        let extractCmd;
        if (process.platform === 'win32') {
          // Windows: 使用 tar 或其他可用的解压工具
          extractCmd = `tar -xzf "${tarballPath}" -C "${DEPS_DIR}"`;
        } else {
          // macOS/Linux
          extractCmd = `tar -xzf "${tarballPath}" -C "${DEPS_DIR}"`;
        }
        
        try {
          execSync(extractCmd);
          console.log('解压完成');
          
          // 创建包含目录的符号链接
          if (!fs.existsSync(path.join(DEPS_DIR, 'spdlog'))) {
            fs.mkdirSync(path.join(DEPS_DIR, 'spdlog'), { recursive: true });
            fs.mkdirSync(path.join(DEPS_DIR, 'spdlog', 'include'), { recursive: true });
            
            // 复制 spdlog 头文件到 include 目录
            const srcDir = path.join(SPDLOG_DIR, 'include', 'spdlog');
            const destDir = path.join(SPDLOG_INCLUDE_DIR, 'spdlog');
            
            if (!fs.existsSync(destDir)) {
              fs.mkdirSync(destDir, { recursive: true });
            }
            
            copyFolderRecursiveSync(srcDir, path.join(SPDLOG_INCLUDE_DIR));
            
            console.log('设置完成');
          }
          
          // 清理下载的 tarball
          fs.unlinkSync(tarballPath);
        } catch (error) {
          console.error('解压错误:', error);
        }
      });
    });
  }).on('error', (err) => {
    fs.unlinkSync(tarballPath);
    console.error('下载错误:', err);
  });
}

// 递归复制文件夹
function copyFolderRecursiveSync(source, targetFolder) {
  // 创建目标文件夹
  const targetPath = path.join(targetFolder, path.basename(source));
  if (!fs.existsSync(targetPath)) {
    fs.mkdirSync(targetPath, { recursive: true });
  }

  // 复制文件
  if (fs.lstatSync(source).isDirectory()) {
    const files = fs.readdirSync(source);
    files.forEach(function (file) {
      const curSource = path.join(source, file);
      if (fs.lstatSync(curSource).isDirectory()) {
        copyFolderRecursiveSync(curSource, targetPath);
      } else {
        fs.copyFileSync(curSource, path.join(targetPath, file));
      }
    });
  }
}

// 执行下载
downloadAndExtractSpdlog(); 
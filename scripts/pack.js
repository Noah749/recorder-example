'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const tar = require('tar');
const pkg = require('../package.json');

const DIST_DIR = path.join(__dirname, '..', 'dist');
const PREBUILDS_DIR = path.join(__dirname, '..', 'prebuilds');

// 创建目录
if (!fs.existsSync(DIST_DIR)) {
  fs.mkdirSync(DIST_DIR, { recursive: true });
}
if (!fs.existsSync(PREBUILDS_DIR)) {
  fs.mkdirSync(PREBUILDS_DIR, { recursive: true });
}

// 打包流程
async function pack() {
  try {
    console.log('正在清理旧的构建文件...');
    // 清理旧的构建文件
    if (fs.existsSync(path.join(DIST_DIR, `${pkg.name}-v${pkg.version}.tgz`))) {
      fs.unlinkSync(path.join(DIST_DIR, `${pkg.name}-v${pkg.version}.tgz`));
    }
    
    // 确保已经构建了二进制文件
    console.log('确保已构建二进制文件...');
    try {
      execSync('npm run build', { stdio: 'inherit' });
    } catch (error) {
      console.error('构建失败:', error);
      process.exit(1);
    }
    
    // 复制当前构建的二进制文件到 prebuilds 目录
    console.log('正在复制二进制文件到预编译目录...');
    const platform = process.platform;
    const arch = process.arch;
    const buildPath = path.join(__dirname, '..', 'build', 'Release', 'meeting_recorder.node');
    const targetDir = path.join(PREBUILDS_DIR, `${platform}-${arch}`);
    
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
    }
    
    if (fs.existsSync(buildPath)) {
      const targetPath = path.join(targetDir, `node.napi.node`);
      fs.copyFileSync(buildPath, targetPath);
      console.log(`已复制二进制文件到 ${targetPath}`);
    } else {
      console.error('未找到构建的二进制文件');
      process.exit(1);
    }
    
    // 创建临时打包目录
    const TEMP_DIR = path.join(__dirname, '..', 'temp-package');
    if (fs.existsSync(TEMP_DIR)) {
      fs.rmSync(TEMP_DIR, { recursive: true, force: true });
    }
    fs.mkdirSync(TEMP_DIR, { recursive: true });
    
    // 复制必要文件到临时目录
    console.log('准备打包文件...');
    
    // 复制和调整 package.json
    const packageJson = JSON.parse(JSON.stringify(pkg));
    delete packageJson.devDependencies;
    
    // 确保没有gypfile标记和binding.gyp引用
    delete packageJson.gypfile;
    if (packageJson.files) {
      packageJson.files = packageJson.files.filter(file => file !== 'binding.gyp' && !file.includes('src/'));
    }
    
    fs.writeFileSync(
      path.join(TEMP_DIR, 'package.json'),
      JSON.stringify(packageJson, null, 2)
    );
    
    fs.copyFileSync(path.join(__dirname, '..', 'index.js'), path.join(TEMP_DIR, 'index.js'));
    fs.copyFileSync(path.join(__dirname, '..', 'README.md'), path.join(TEMP_DIR, 'README.md'));
    
    // 复制预构建文件
    fs.mkdirSync(path.join(TEMP_DIR, 'prebuilds'), { recursive: true });
    copyDirSync(PREBUILDS_DIR, path.join(TEMP_DIR, 'prebuilds'));
    
    // 在临时目录中打包
    console.log('正在创建 npm 包...');
    const currentDir = process.cwd();
    process.chdir(TEMP_DIR);
    const packOutput = execSync('npm pack', { encoding: 'utf8' });
    console.log(packOutput);
    
    // 移动包到 dist 目录
    const packageFileName = packOutput.trim();
    if (fs.existsSync(packageFileName)) {
      fs.renameSync(packageFileName, path.join('..', 'dist', packageFileName));
      console.log(`包已移动到 ${path.join('..', 'dist', packageFileName)}`);
    }
    
    // 恢复工作目录并清理
    process.chdir(currentDir);
    fs.rmSync(TEMP_DIR, { recursive: true, force: true });
    
    console.log('打包完成！');
  } catch (error) {
    console.error('打包过程中出错:', error);
    process.exit(1);
  }
}

// 获取当前 Node.js 的 ABI 版本
function getNodeAbi() {
  try {
    const nodeVersion = process.versions.node;
    const abiOutput = execSync(`node -p "process.versions.modules"`, { encoding: 'utf8' });
    return abiOutput.trim();
  } catch (error) {
    console.error('获取 Node.js ABI 版本失败:', error);
    return null;
  }
}

// 递归复制目录
function copyDirSync(src, dest) {
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }
  
  const entries = fs.readdirSync(src, { withFileTypes: true });
  
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    
    if (entry.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

// 执行打包
pack(); 
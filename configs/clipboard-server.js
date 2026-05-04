#!/usr/bin/env node

/**
 * clipboard-server.js
 *
 * 剪贴板图片服务
 * 接收浏览器上传的图片，使用 xclip 写入容器剪贴板
 */

const express = require('express');
const multer = require('multer');
const { spawn } = require('child_process');
const fs = require('fs').promises;
const path = require('path');

const app = express();
const PORT = 10009;

app.use(express.json({ limit: '2mb' }));

// 配置 multer 处理文件上传
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 限制 10MB
    files: 1
  },
  fileFilter: (req, file, cb) => {
    // 只接受图片格式
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('只支持图片格式'));
    }
  }
});

// 健康检查端点
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'clipboard-server' });
});

// 文本剪贴板 API：作为 noVNC 原生 clipboard 通道的兜底。
// GET 只读取 X11 CLIPBOARD，不修改容器剪贴板。
app.get('/api/clipboard-text', (req, res) => {
  const child = spawn('xclip', ['-selection', 'clipboard', '-target', 'UTF8_STRING', '-o']);
  const chunks = [];
  child.stdout.on('data', (b) => chunks.push(b));
  child.stderr.on('data', () => {});
  child.on('error', () => res.status(500).json({ error: '读取文本剪贴板失败' }));
  child.on('close', (code) => {
    if (code !== 0 || chunks.length === 0) return res.status(404).json({ error: '没有文本剪贴板内容' });
    res.setHeader('Cache-Control', 'no-store');
    res.json({ text: Buffer.concat(chunks).toString('utf8') });
  });
});

// POST 写入容器 X11 文本剪贴板。图片接口仍独立使用 image/png，避免格式互相误判。
app.post('/api/clipboard-text', async (req, res) => {
  const text = typeof req.body?.text === 'string' ? req.body.text : '';
  if (!text) {
    return res.status(400).json({
      error: '没有文本内容',
      code: 'NO_TEXT'
    });
  }
  if (Buffer.byteLength(text, 'utf8') > 1024 * 1024) {
    return res.status(400).json({
      error: '文本过大（最大 1MB）',
      code: 'TEXT_TOO_LARGE'
    });
  }

  const tempFileName = `clipboard-text-${Date.now()}.txt`;
  const tempPath = path.join('/tmp', tempFileName);

  try {
    await fs.writeFile(tempPath, text, 'utf8');
    const child = spawn('xclip',
      ['-selection', 'clipboard', '-target', 'UTF8_STRING', '-i', tempPath],
      { detached: true, stdio: 'ignore' });
    child.unref();

    setTimeout(() => {
      fs.unlink(tempPath).catch(err => {
        if (err.code !== 'ENOENT') {
          console.warn(`[clipboard] 清理文本临时文件失败: ${err.message}`);
        }
      });
    }, 5000);

    res.json({ success: true, message: '文本已同步到剪贴板', size: Buffer.byteLength(text, 'utf8') });
  } catch (error) {
    console.error('[clipboard] 文本剪贴板写入失败:', error);
    res.status(500).json({ error: '写入文本剪贴板失败', code: 'XCLIP_ERROR' });
  }
});

// 反向：读取容器当前 X11 剪贴板里的 image/png
// 无图时 xclip 退出码非 0 或 stdout 空，返回 404
app.get('/api/clipboard-image', (req, res) => {
  const child = spawn('xclip', ['-selection', 'clipboard', '-target', 'image/png', '-o']);
  const chunks = [];
  child.stdout.on('data', (b) => chunks.push(b));
  child.stderr.on('data', () => {});
  child.on('error', () => res.status(500).end());
  child.on('close', (code) => {
    if (code !== 0 || chunks.length === 0) return res.status(404).end();
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'no-store');
    res.end(Buffer.concat(chunks));
  });
});

// 图片剪贴板 API
app.post('/api/clipboard-image', upload.single('image'), async (req, res) => {
  const startTime = Date.now();

  try {
    if (!req.file) {
      return res.status(400).json({
        error: '没有上传文件',
        code: 'NO_FILE'
      });
    }

    console.log(`[clipboard] 收到图片: ${req.file.mimetype}, ${(req.file.size / 1024).toFixed(2)} KB`);

    // 生成临时文件路径
    const tempFileName = `pasted-image-${Date.now()}.png`;
    const tempPath = path.join('/tmp', tempFileName);

    // 写入临时文件
    await fs.writeFile(tempPath, req.file.buffer);

    console.log(`[clipboard] 临时文件已保存: ${tempPath}`);

    // 使用 xclip 将图片写入容器剪贴板
    // xclip -i 会 fork 守护进程持有 clipboard，阻塞到别人 paste 才退出；
    // 这里必须 detach 后立刻返回响应，让前端再 send Ctrl+V 触发 paste，否则会死锁。
    try {
      const child = spawn('xclip',
        ['-selection', 'clipboard', '-target', 'image/png', '-i', tempPath],
        { detached: true, stdio: 'ignore' });
      child.unref();
      console.log(`[clipboard] xclip 后台启动 pid=${child.pid}`);

      // 延迟 5 秒清理临时文件，确保 xclip 已读入数据
      setTimeout(() => {
        fs.unlink(tempPath).catch(err => {
          if (err.code !== 'ENOENT') {
            console.warn(`[clipboard] 清理临时文件失败: ${err.message}`);
          }
        });
      }, 5000);
    } catch (error) {
      console.error('[clipboard] xclip 启动失败:', error);
      throw new Error('写入剪贴板失败');
    }

    const elapsed = Date.now() - startTime;
    console.log(`[clipboard] 处理完成，耗时: ${elapsed}ms`);

    res.json({
      success: true,
      message: '图片已同步到剪贴板',
      size: req.file.size,
      elapsed: elapsed
    });

  } catch (error) {
    console.error('[clipboard] 处理失败:', error);

    res.status(500).json({
      error: error.message,
      code: 'PROCESSING_ERROR'
    });
  }
});

// 错误处理
app.use((error, req, res, next) => {
  if (error instanceof multer.MulterError) {
    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({
        error: '文件过大（最大 10MB）',
        code: 'FILE_TOO_LARGE'
      });
    }
    return res.status(400).json({
      error: error.message,
      code: 'UPLOAD_ERROR'
    });
  }

  if (error.message === '只支持图片格式') {
    return res.status(400).json({
      error: error.message,
      code: 'INVALID_FILE_TYPE'
    });
  }

  console.error('[clipboard] 未处理的错误:', error);
  res.status(500).json({
    error: '服务器内部错误',
    code: 'INTERNAL_ERROR'
  });
});

// 启动服务器
app.listen(PORT, '127.0.0.1', () => {
  console.log(`[clipboard] 服务已启动，监听端口: ${PORT}`);
  console.log(`[clipboard] 健康检查: http://127.0.0.1:${PORT}/health`);
  console.log(`[clipboard] API 端点: http://127.0.0.1:${PORT}/api/clipboard-image`);
});

// 优雅关闭
process.on('SIGTERM', () => {
  console.log('[clipboard] 收到 SIGTERM 信号，正在关闭...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('[clipboard] 收到 SIGINT 信号，正在关闭...');
  process.exit(0);
});

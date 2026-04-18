/*
 * custom-clipboard-image.js
 *
 * 增强版 noVNC 剪贴板功能
 * 支持图片和文本的自动同步粘贴
 */

(function() {
  'use strict';

  // 加载提示元素
  const loading = document.getElementById('clipboard-loading') || createLoadingElement();

  function createLoadingElement() {
    const div = document.createElement('div');
    div.id = 'clipboard-loading';
    div.style.cssText = `
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      background: rgba(0, 0, 0, 0.8);
      color: white;
      padding: 20px 40px;
      border-radius: 8px;
      font-size: 16px;
      z-index: 9999;
      display: none;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    `;
    document.body.appendChild(div);
    return div;
  }

  // 显示加载提示
  function showLoading(message, type = '') {
    loading.textContent = message;
    loading.className = type;
    loading.style.display = 'block';
  }

  // 隐藏加载提示
  function hideLoading() {
    setTimeout(() => {
      loading.style.display = 'none';
    }, 1500);
  }

  // 检查是否在 noVNC 焦点
  // 放宽规则：只要不是在输入框/可编辑元素里输入，就认为是在 noVNC 粘贴
  // 因为点击 canvas 后 document.activeElement 常常仍是 body，不会进入 #noVNC_container
  function isNoVNCFocused() {
    const activeElement = document.activeElement;
    if (!activeElement) return true;

    if (activeElement.tagName === 'INPUT' ||
        activeElement.tagName === 'TEXTAREA' ||
        activeElement.isContentEditable) {
      return false;
    }

    return true;
  }

  // 构造剪贴板 API URL（同 audio-bar.js 的 getAudioWebSocketUrl 写法）
  // noVNC 挂在 /proxy/10004/ 下 → 走 /proxy/10009/api/clipboard-image
  // 开发直连 → /api/clipboard-image
  function getClipboardApiUrl() {
    const basePath = location.pathname.match(/\/proxy\/10004\//) ? '/proxy/10009/' : '/';
    return location.protocol + '//' + location.host + basePath + 'api/clipboard-image';
  }

  // 上传图片到服务器
  async function uploadImageToServer(blob) {
    const formData = new FormData();
    formData.append('image', blob, 'pasted-image.png');

    const response = await fetch(getClipboardApiUrl(), {
      method: 'POST',
      body: formData
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: '上传失败' }));
      throw new Error(error.error || '上传失败');
    }

    return await response.json();
  }

  // 发送 Ctrl+V 到容器（完整 Ctrl↓ V↓ V↑ Ctrl↑ 序列）
  async function sendCtrlVToContainer() {
    const rfb = (window.UI && window.UI.rfb) || window.rfb;
    if (!rfb || typeof rfb.sendKey !== 'function') {
      throw new Error('noVNC RFB 实例不可用');
    }
    const XK_Control_L = 0xffe3;
    const XK_V = 0x0076;
    rfb.sendKey(XK_Control_L, 'ControlLeft', true);
    rfb.sendKey(XK_V, 'KeyV', true);
    rfb.sendKey(XK_V, 'KeyV', false);
    rfb.sendKey(XK_Control_L, 'ControlLeft', false);
  }

  // 从剪贴板项中提取图片
  async function getImageFromClipboardItem(item) {
    const types = item.types;
    const imageType = types.find(t => t.startsWith('image/'));

    if (imageType) {
      return await item.getType(imageType);
    }

    return null;
  }

  // 检查剪贴板项是否包含文本
  function hasTextInClipboardItem(item) {
    return item.types.includes('text/plain');
  }

  // 主处理函数：Ctrl+V
  async function handleCtrlV(e) {
    e.preventDefault();

    // 检查焦点
    if (!isNoVNCFocused()) {
      console.log('[clipboard] 不在 noVNC 焦点区域，跳过处理');
      return;
    }

    try {
      showLoading('正在读取剪贴板...');

      // 读取剪贴板
      const clipboardItems = await navigator.clipboard.read();

      if (!clipboardItems || clipboardItems.length === 0) {
        showLoading('剪贴板为空', 'error');
        hideLoading();
        return;
      }

      let hasImage = false;
      let hasText = false;

      // 遍历剪贴板项
      for (const item of clipboardItems) {
        // 优先处理图片
        const imageBlob = await getImageFromClipboardItem(item);
        if (imageBlob) {
          hasImage = true;

          // 检查文件大小（限制 10MB）
          if (imageBlob.size > 10 * 1024 * 1024) {
            showLoading('图片过大（>10MB）', 'error');
            hideLoading();
            return;
          }

          showLoading('正在同步图片...');

          // 上传到服务器
          await uploadImageToServer(imageBlob);

          // 等待服务器处理（写入容器剪贴板）
          await new Promise(resolve => setTimeout(resolve, 300));

          // 发送 Ctrl+V 到容器
          await sendCtrlVToContainer();

          showLoading('✓ 粘贴成功', 'success');
          hideLoading();
          break;
        }

        // 检查是否有文本
        if (hasTextInClipboardItem(item)) {
          hasText = true;
        }
      }

      // 如果没有图片，但有文本，使用 noVNC 原生方法
      if (!hasImage && hasText) {
        const text = await navigator.clipboard.readText();

        if (text) {
          showLoading('正在同步文本...');

          // 使用 noVNC 原生剪贴板方法
          if (window.UI && window.UI.rfb) {
            window.UI.rfb.clipboardPasteFrom(text);

            // 自动发送 Ctrl+V
            await new Promise(resolve => setTimeout(resolve, 100));
            await sendCtrlVToContainer();

            showLoading('✓ 文本已粘贴', 'success');
            hideLoading();
          }
        }
      }

      // 既没有图片也没有文本
      if (!hasImage && !hasText) {
        showLoading('剪贴板没有可粘贴的内容', 'error');
        hideLoading();
      }

    } catch (error) {
      console.error('[clipboard] 粘贴失败:', error);

      // 处理权限错误
      if (error.name === 'NotAllowedError') {
        showLoading('✗ 请允许剪贴板访问权限', 'error');
      } else if (error.name === 'NotFoundError') {
        showLoading('✗ 剪贴板为空', 'error');
      } else {
        showLoading('✗ 粘贴失败: ' + error.message, 'error');
      }

      hideLoading();
    }
  }

  // 请求剪贴板权限
  async function requestClipboardPermission() {
    try {
      if ('permissions' in navigator) {
        const result = await navigator.permissions.query({ name: 'clipboard-read' });
        console.log('[clipboard] 剪贴板权限状态:', result.state);

        if (result.state === 'prompt') {
          console.log('[clipboard] 需要用户授权剪贴板访问权限');
        }

        // 监听权限变化
        result.addEventListener('change', () => {
          console.log('[clipboard] 剪贴板权限状态变更:', result.state);
        });
      }
    } catch (error) {
      console.log('[clipboard] 浏览器不支持 permissions API');
    }
  }

  // 初始化
  function init() {
    console.log('[clipboard] 初始化增强剪贴板功能');

    // 检查浏览器支持
    if (!navigator.clipboard || !navigator.clipboard.read) {
      console.error('[clipboard] 浏览器不支持剪贴板 API');
      return;
    }

    // 请求权限
    requestClipboardPermission();

    // 监听键盘事件（同时接受 Ctrl+V 与 macOS 的 Cmd+V）
    // 使用 capture 阶段，抢在 noVNC 的 keydown 处理之前接管，避免被 stopPropagation 截掉
    const keyHandler = (e) => {
      if (!((e.ctrlKey || e.metaKey) && (e.key === 'v' || e.key === 'V'))) return;
      if (!isNoVNCFocused()) return;
      e.stopPropagation();
      handleCtrlV(e);
    };
    document.addEventListener('keydown', keyHandler, true);
    window.addEventListener('keydown', keyHandler, true);

    console.log('[clipboard] 已就绪，按 Ctrl+V / Cmd+V 粘贴图片或文本');
  }

  // 页面加载完成后初始化
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();

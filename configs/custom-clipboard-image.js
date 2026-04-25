/*
 * custom-clipboard-image.js
 *
 * Mac↔容器 图片同步：双按钮注入到 noVNC 自带 Clipboard 面板。
 * 不监听 Ctrl+V / Ctrl+C —— 全部按键交给 noVNC 原生，
 * 容器内复制粘贴和终端 Ctrl+C 中断永不被脚本污染。
 *
 * 按钮 A：把 Mac 剪贴板里的图片粘到容器
 * 按钮 B：把容器剪贴板里的图片拷到 Mac
 *
 * Mac↔容器 文本同步：用 noVNC 原生 textarea。
 */

(function() {
  'use strict';

  // 轻量 i18n：按浏览器语言选中/英文。zh 系列走中文，其余走英文。
  const I18N = {
    'zh': {
      btn_mac_to_container: '📋 把 Mac 图片粘到容器',
      btn_mac_to_container_title: '读取 Mac 剪贴板里的图片，上传到容器并粘贴到当前焦点',
      btn_container_to_mac: '📥 把容器图片拷到 Mac',
      btn_container_to_mac_title: '读取容器剪贴板里的图片，写入 Mac 系统剪贴板',
      read_mac_failed: '✗ 读取 Mac 剪贴板失败：',
      no_image_in_mac: 'Mac 剪贴板没有图片',
      image_too_large: '图片过大（>10MB）',
      syncing_to_container: '正在同步图片到容器...',
      pasted_to_container: '✓ 已粘到容器',
      sync_failed: '✗ 同步失败：',
      reading_from_container: '正在从容器读取图片...',
      no_image_in_container: '容器剪贴板没有图片',
      copied_to_mac: '✓ 已拷到 Mac 剪贴板',
      copy_failed: '✗ 拷贝失败：',
      api_unsupported: '浏览器不支持剪贴板 API'
    },
    'en': {
      btn_mac_to_container: '📋 Paste Mac image into container',
      btn_mac_to_container_title: 'Read image from Mac clipboard, upload to container and paste at focus',
      btn_container_to_mac: '📥 Copy container image to Mac',
      btn_container_to_mac_title: 'Read image from container clipboard, write to Mac system clipboard',
      read_mac_failed: '✗ Failed to read Mac clipboard: ',
      no_image_in_mac: 'No image in Mac clipboard',
      image_too_large: 'Image too large (>10MB)',
      syncing_to_container: 'Syncing image to container...',
      pasted_to_container: '✓ Pasted to container',
      sync_failed: '✗ Sync failed: ',
      reading_from_container: 'Reading image from container...',
      no_image_in_container: 'No image in container clipboard',
      copied_to_mac: '✓ Copied to Mac clipboard',
      copy_failed: '✗ Copy failed: ',
      api_unsupported: 'Browser does not support Clipboard API'
    }
  };
  const T = (navigator.language || 'en').toLowerCase().startsWith('zh') ? I18N.zh : I18N.en;

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

  function showLoading(message, type = '') {
    loading.textContent = message;
    loading.className = type;
    loading.style.display = 'block';
  }

  function hideLoading() {
    setTimeout(() => {
      loading.style.display = 'none';
    }, 1500);
  }

  // noVNC 挂在 /proxy/10004/ 下 → 走 /proxy/10009/api/clipboard-image
  // 开发直连 → /api/clipboard-image
  function getClipboardApiUrl() {
    const basePath = location.pathname.match(/\/proxy\/10004\//) ? '/proxy/10009/' : '/';
    return location.protocol + '//' + location.host + basePath + 'api/clipboard-image';
  }

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

  // 通过 RFB 给容器注入 Ctrl+V（完整 Ctrl↓ V↓ V↑ Ctrl↑ 序列）
  function sendCtrlVToContainer() {
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

  async function readImageFromMacClipboard() {
    if (!navigator.clipboard || !navigator.clipboard.read) {
      throw new Error(T.api_unsupported);
    }
    const items = await navigator.clipboard.read();
    for (const item of items) {
      const imageType = item.types.find(t => t.startsWith('image/'));
      if (imageType) {
        return await item.getType(imageType);
      }
    }
    return null;
  }

  // 按钮 A：Mac → 容器
  async function handleMacToContainer() {
    let imageBlob;
    try {
      imageBlob = await readImageFromMacClipboard();
    } catch (err) {
      showLoading(T.read_mac_failed + (err.message || ''), 'error');
      hideLoading();
      return;
    }

    if (!imageBlob) {
      showLoading(T.no_image_in_mac, 'error');
      hideLoading();
      return;
    }

    if (imageBlob.size > 10 * 1024 * 1024) {
      showLoading(T.image_too_large, 'error');
      hideLoading();
      return;
    }

    try {
      showLoading(T.syncing_to_container);
      await uploadImageToServer(imageBlob);
      // 等服务端 xclip 把图片塞进 X11 CLIPBOARD
      await new Promise(resolve => setTimeout(resolve, 300));
      sendCtrlVToContainer();
      showLoading(T.pasted_to_container, 'success');
      hideLoading();
    } catch (err) {
      console.warn('[clipboard] Mac→container sync failed:', err && err.message);
      showLoading(T.sync_failed + (err.message || ''), 'error');
      hideLoading();
    }
  }

  // 按钮 B：容器 → Mac
  async function handleContainerToMac() {
    try {
      showLoading(T.reading_from_container);
      const resp = await fetch(getClipboardApiUrl(), { method: 'GET' });
      if (resp.status === 404) {
        showLoading(T.no_image_in_container, 'error');
        hideLoading();
        return;
      }
      if (!resp.ok) {
        throw new Error('GET ' + resp.status);
      }
      const blob = await resp.blob();
      if (!blob || !blob.size) {
        showLoading(T.no_image_in_container, 'error');
        hideLoading();
        return;
      }
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
      showLoading(T.copied_to_mac, 'success');
      hideLoading();
    } catch (err) {
      console.warn('[clipboard] container→Mac sync failed:', err && err.message);
      showLoading(T.copy_failed + (err.message || ''), 'error');
      hideLoading();
    }
  }

  function makeButton(text, title, onClick) {
    const btn = document.createElement('button');
    btn.textContent = text;
    btn.title = title;
    btn.style.cssText = `
      display: block;
      width: 100%;
      margin-top: 8px;
      padding: 8px 12px;
      background: rgba(0, 120, 215, 0.85);
      color: white;
      border: none;
      border-radius: 4px;
      font-size: 13px;
      cursor: pointer;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      user-select: none;
    `;
    btn.addEventListener('mouseenter', () => {
      btn.style.background = 'rgba(0, 120, 215, 1)';
    });
    btn.addEventListener('mouseleave', () => {
      btn.style.background = 'rgba(0, 120, 215, 0.85)';
    });
    btn.addEventListener('click', onClick);
    return btn;
  }

  function injectButtons() {
    const panel = document.getElementById('noVNC_clipboard');
    if (!panel) {
      console.warn('[clipboard] #noVNC_clipboard 面板未找到，按钮未注入');
      return false;
    }
    if (panel.querySelector('.custom-clipboard-buttons')) {
      return true;
    }

    const wrap = document.createElement('div');
    wrap.className = 'custom-clipboard-buttons';
    wrap.style.cssText = 'margin-top: 6px;';

    wrap.appendChild(makeButton(
      T.btn_mac_to_container,
      T.btn_mac_to_container_title,
      handleMacToContainer
    ));
    wrap.appendChild(makeButton(
      T.btn_container_to_mac,
      T.btn_container_to_mac_title,
      handleContainerToMac
    ));

    panel.appendChild(wrap);
    return true;
  }

  function init() {
    console.log('[clipboard] 初始化 Mac↔容器 图片按钮');
    if (!navigator.clipboard || !navigator.clipboard.read || !navigator.clipboard.write) {
      console.warn('[clipboard] 浏览器不支持剪贴板 API，按钮未注入');
      return;
    }
    // noVNC 的 #noVNC_clipboard 是 vnc.html 静态 DOM，DOMContentLoaded 后即可拿到。
    // 但脚本以 defer/end-of-body 形式加载，部分时序下 panel 可能晚到，做一次小重试。
    if (injectButtons()) {
      console.log('[clipboard] 已就绪，按钮注入到 noVNC Clipboard 面板');
      return;
    }
    let tries = 0;
    const timer = setInterval(() => {
      if (injectButtons() || ++tries >= 30) {
        clearInterval(timer);
      }
    }, 200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();

/*
 * custom-clipboard-image.js
 *
 * Mac↔容器 图片同步：双按钮注入到 noVNC 自带 Clipboard 面板。
 * Mac↔容器 文本同步：复用 noVNC 原生 RFB clipboard 文本通道。
 * 不监听 Ctrl+C —— 容器内 Ctrl+C 和终端中断永不被脚本污染。
 *
 * 按钮 A：把 Mac 剪贴板里的图片粘到容器
 * 按钮 B：把容器剪贴板里的图片拷到 Mac
 *
 * Mac↔容器 文本同步：
 * - 容器复制文本后，自动尝试写入 Mac 系统剪贴板。
 * - Mac 在 noVNC 页面粘贴文本时，写入容器剪贴板并主动粘贴到当前焦点。
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
      api_unsupported: '浏览器不支持剪贴板 API',
      text_copied_to_mac: '✓ 文本已同步到 Mac 剪贴板',
      text_clipboard_blocked: '文本已到 noVNC 剪贴板面板，浏览器未授权写入 Mac 剪贴板',
      text_pasted_to_container: '✓ 文本已粘到容器'
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
      api_unsupported: 'Browser does not support Clipboard API',
      text_copied_to_mac: '✓ Text synced to Mac clipboard',
      text_clipboard_blocked: 'Text is in the noVNC clipboard panel. Browser permission blocked Mac clipboard write',
      text_pasted_to_container: '✓ Text pasted to container'
    }
  };
  const T = (navigator.language || 'en').toLowerCase().startsWith('zh') ? I18N.zh : I18N.en;
  let lastTextSentToContainer = '';
  let lastTextCopiedToMac = '';
  let lastTextSeenFromContainer = '';

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

  function getClipboardTextApiUrl() {
    const basePath = location.pathname.match(/\/proxy\/10004\//) ? '/proxy/10009/' : '/';
    return location.protocol + '//' + location.host + basePath + 'api/clipboard-text';
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

  function getRfb() {
    return (window.UI && window.UI.rfb) || window.rfb || null;
  }

  function isEditableElement(el) {
    if (!el) return false;
    const tag = (el.tagName || '').toLowerCase();
    return tag === 'textarea' || tag === 'input' || el.isContentEditable;
  }

  function setNoVncClipboardText(text) {
    const textarea = document.getElementById('noVNC_clipboard_text');
    if (textarea) {
      textarea.value = text;
    }
  }

  async function writeTextToMacClipboard(text) {
    if (!text || !navigator.clipboard || !navigator.clipboard.writeText) {
      return false;
    }
    try {
      await navigator.clipboard.writeText(text);
      lastTextCopiedToMac = text;
      return true;
    } catch (err) {
      console.warn('[clipboard] text write to Mac clipboard blocked:', err && err.message);
      return false;
    }
  }

  function sendTextToContainerClipboard(text) {
    const rfb = getRfb();
    if (!rfb || typeof rfb.clipboardPasteFrom !== 'function') {
      throw new Error('noVNC RFB 剪贴板不可用');
    }
    lastTextSentToContainer = text;
    setNoVncClipboardText(text);
    rfb.clipboardPasteFrom(text);
  }

  async function writeTextToContainerClipboard(text) {
    const response = await fetch(getClipboardTextApiUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text })
    });
    if (!response.ok) {
      const error = await response.json().catch(() => ({ error: '写入文本剪贴板失败' }));
      throw new Error(error.error || '写入文本剪贴板失败');
    }
  }

  async function syncTextToContainer(text) {
    try {
      sendTextToContainerClipboard(text);
    } catch (err) {
      console.warn('[clipboard] noVNC text clipboard failed, falling back to xclip:', err && err.message);
      await writeTextToContainerClipboard(text);
      lastTextSentToContainer = text;
      setNoVncClipboardText(text);
    }
  }

  async function handleRfbClipboardText(e) {
    const text = e && e.detail && typeof e.detail.text === 'string' ? e.detail.text : '';
    if (!text || text === lastTextSentToContainer || text === lastTextCopiedToMac) {
      return;
    }

    lastTextSeenFromContainer = text;
    await syncTextFromContainerToMac(text);
  }

  async function syncTextFromContainerToMac(text) {
    setNoVncClipboardText(text);
    const ok = await writeTextToMacClipboard(text);
    if (!ok) {
      showLoading(T.text_clipboard_blocked, 'error');
      hideLoading();
    }
  }

  async function handleBrowserPaste(e) {
    if (isEditableElement(e.target) && e.target.id !== 'noVNC_canvas') {
      return;
    }
    const text = e.clipboardData && e.clipboardData.getData('text/plain');
    if (!text) {
      return;
    }

    try {
      e.preventDefault();
      e.stopPropagation();
      await syncTextToContainer(text);
      setTimeout(sendCtrlVToContainer, 80);
      showLoading(T.text_pasted_to_container, 'success');
      hideLoading();
    } catch (err) {
      console.warn('[clipboard] Mac text paste to container failed:', err && err.message);
    }
  }

  async function pollContainerTextClipboard() {
    try {
      const resp = await fetch(getClipboardTextApiUrl(), { method: 'GET', cache: 'no-store' });
      if (resp.status === 404) return;
      if (!resp.ok) throw new Error('GET ' + resp.status);
      const data = await resp.json();
      const text = typeof data.text === 'string' ? data.text : '';
      if (!text || text === lastTextSeenFromContainer || text === lastTextSentToContainer || text === lastTextCopiedToMac) {
        return;
      }
      lastTextSeenFromContainer = text;
      await syncTextFromContainerToMac(text);
    } catch (err) {
      console.warn('[clipboard] text clipboard polling failed:', err && err.message);
    }
  }

  function initTextClipboardBridge() {
    if (document.__webclawTextClipboardPasteBridge) {
      return;
    }
    document.__webclawTextClipboardPasteBridge = true;
    document.addEventListener('paste', handleBrowserPaste, true);

    // 监听 Cmd+V / Ctrl+V，从 Mac 剪贴板同步到容器
    let lastCtrlVTime = 0;
    document.addEventListener('keydown', async (e) => {
      const isCmdOrCtrl = e.metaKey || e.ctrlKey;
      const isVKey = e.key === 'v' || e.key === 'V';

      if (isCmdOrCtrl && isVKey) {
        const now = Date.now();
        if (now - lastCtrlVTime < 500) {
          e.preventDefault();
          e.stopPropagation();
          return;
        }
        lastCtrlVTime = now;

        // 阻止原始按键，等我们同步完成后再发送
        e.preventDefault();
        e.stopPropagation();

        try {
          const text = await navigator.clipboard.readText();
          if (text && text.trim()) {
            console.log('[clipboard] Ctrl+V detected, syncing Mac clipboard: ' + text.substring(0, 30));
            
            // 同步到容器剪贴板
            await fetch(getClipboardTextApiUrl(), {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ text })
            });
            
            console.log('[clipboard] ✓ Synced, sending Ctrl+V to container');
            
            // 等待 xclip 完成，然后手动发送 Ctrl+V 到容器
            setTimeout(() => {
              sendCtrlVToContainer();
            }, 100);
          }
        } catch (err) {
          console.warn('[clipboard] Sync failed:', err && err.message);
        }
      }
    }, true);
    let tries = 0;
    const timer = setInterval(() => {
      const rfb = getRfb();
      if (rfb && typeof rfb.addEventListener === 'function') {
        if (!rfb.__webclawTextClipboardBridge) {
          rfb.addEventListener('clipboard', handleRfbClipboardText);
          rfb.__webclawTextClipboardBridge = true;
          console.log('[clipboard] 文本剪贴板桥已启用');
        }
        clearInterval(timer);
      } else if (++tries >= 50) {
        clearInterval(timer);
        console.warn('[clipboard] RFB 未就绪，文本剪贴板桥未启用');
      }
    }, 200);
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
    initTextClipboardBridge();
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

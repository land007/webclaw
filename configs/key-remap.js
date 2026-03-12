/**
 * key-remap.js - noVNC 键盘映射配置
 *
 * 功能：
 * 1. 单键映射：F1/F2 → ESC，F3 → Ctrl+Alt+Del
 * 2. Shift 组合映射：Shift+Tab → Tab，Shift+Delete → Delete 等
 * 3. 所有映射可在下方配置区域集中修改
 * 4. 国际化支持（中文/English）
 * 5. 按 F10 重新显示提示信息
 *
 * 使用说明：
 * - 修改下面的 MAPPINGS 配置对象即可重新定义映射
 * - enabled: false 可以禁用某个映射
 * - type: 'single' 表示单键直接映射，'shift' 表示 Shift 组合键映射
 *
 * 默认映射（Mac 用户友好）：
 *   F1  → ESC           （退出 Vim/编辑器）
 *   F2  → ESC（备用）    （ESC 第二选择）
 *   F3  → Ctrl+Alt+Del  （任务管理器）
 *   F10 → 重新显示提示   （Show hints again）
 *   Shift+Tab  → Tab
 *   Shift+Delete → Delete
 *   等...
 */
(function () {
  'use strict';

  // ═══════════════════════════════════════════════════════════════
  // 🌐 国际化配置
  // ═══════════════════════════════════════════════════════════════

  const I18N = {
    'zh-CN': {
      hintTitle: '⌨️ 按键映射已启用：',
      tipOr: '或',
      tipClickToolbar: '或点击工具栏的按键按钮',
      btnShowHints: '显示提示',
      btnShowHintsHint: '重新显示按键映射提示（F10）',
      mappings: {
        'Pause': 'Pause → ESC',
        'ScrollLock': 'ScrollLock → Ctrl+Alt+Del',
        'F1': 'F1 → ESC',
        'F2': 'F2 → ESC（备用）',
        'F3': 'F3 → Ctrl+Alt+Del',
        'F10': 'F10 → 重新显示提示',
        'Tab': 'Shift+Tab → Tab',
        'Delete': 'Shift+Delete → Delete',
        'Insert': 'Shift+Insert → Insert',
        'Home': 'Shift+Home → Home',
        'End': 'Shift+End → End',
        'PageUp': 'Shift+PageUp → PageUp',
        'PageDown': 'Shift+PageDown → PageDown'
      }
    },
    'en': {
      hintTitle: '⌨️ Key Mappings Enabled:',
      tipOr: 'or',
      tipClickToolbar: 'or click toolbar buttons',
      btnShowHints: 'Show Hints',
      btnShowHintsHint: 'Show key mapping hints again (F10)',
      mappings: {
        'Pause': 'Pause → ESC',
        'ScrollLock': 'ScrollLock → Ctrl+Alt+Del',
        'F1': 'F1 → ESC',
        'F2': 'F2 → ESC (Alt)',
        'F3': 'F3 → Ctrl+Alt+Del',
        'F10': 'F10 → Show Hints',
        'Tab': 'Shift+Tab → Tab',
        'Delete': 'Shift+Delete → Delete',
        'Insert': 'Shift+Insert → Insert',
        'Home': 'Shift+Home → Home',
        'End': 'Shift+End → End',
        'PageUp': 'Shift+PageUp → PageUp',
        'PageDown': 'Shift+PageDown → PageDown'
      }
    }
  };

  // 检测浏览器语言
  function getLanguage() {
    var lang = navigator.language || navigator.userLanguage;
    if (lang.startsWith('zh')) {
      return 'zh-CN';
    }
    return 'en';
  }

  var currentLang = getLanguage();
  var t = I18N[currentLang];

  // ═══════════════════════════════════════════════════════════════
  // 📝 配置区域 - 所有按键映射都在这里定义
  // ═══════════════════════════════════════════════════════════════

  const MAPPINGS = {
    // ── 单键映射（type: 'single'）───────────────────────────────
    // 适合需要频繁使用的特殊键

    'Pause': {
      enabled: false,  // Mac 键盘通常没有此键
      type: 'single',
      code: 'Pause',
      targetKeysym: 0xFF1B,  // ESC
      targetName: 'Escape',
      hint: 'Pause → ESC (Windows/Linux 键盘)'
    },

    'ScrollLock': {
      enabled: false,  // Mac 键盘通常没有此键
      type: 'single',
      code: 'ScrollLock',
      targetKeysym: 0xFF1B,  // ESC
      targetName: 'Escape',
      hint: 'ScrollLock → Ctrl+Alt+Del (Windows/Linux)',
      isCombo: true,
      comboKeys: ['Ctrl_L', 'Alt_L', 'Delete']
    },

    // Mac 用户友好选项（使用 F1-F12）
    'F1': {
      enabled: true,  // Mac 用户启用
      type: 'single',
      code: 'F1',
      targetKeysym: 0xFF1B,  // ESC
      targetName: 'Escape',
      hint: 'F1 → ESC (Mac 用户推荐)'
    },

    'F2': {
      enabled: true,  // 备用 ESC 键
      type: 'single',
      code: 'F2',
      targetKeysym: 0xFF1B,  // ESC
      targetName: 'Escape',
      hint: 'F2 → ESC (备用)'
    },

    'F3': {
      enabled: true,  // Ctrl+Alt+Del（任务管理器）
      type: 'single',
      code: 'F3',
      targetKeysym: 0xFFFF,  // Delete (组合键的一部分)
      targetName: 'Ctrl+Alt+Del',
      hint: 'F3 → Ctrl+Alt+Del',
      isCombo: true,
      comboKeys: ['Ctrl_L', 'Alt_L', 'Delete']
    },

    'F10': {
      enabled: true,  // 重新显示提示（特殊功能，不发送按键）
      type: 'special',
      code: 'F10',
      action: 'showHints',
      hint: t.mappings['F10']
    },

    // ── Shift 组合键映射（type: 'shift'）───────────────────────────
    // 适合普通按键，避免直接按键时触发浏览器快捷键

    'Tab': {
      enabled: true,
      type: 'shift',  // 需要按 Shift+Tab
      code: 'Tab',
      targetKeysym: 0xFF09,
      targetName: 'Tab',
      hint: 'Shift+Tab → Tab'
    },

    'Delete': {
      enabled: true,
      type: 'shift',  // 需要按 Shift+Delete
      code: 'Delete',
      targetKeysym: 0xFFFF,
      targetName: 'Delete',
      hint: 'Shift+Delete → Delete'
    },

    'Insert': {
      enabled: true,
      type: 'shift',
      code: 'Insert',
      targetKeysym: 0xFF63,
      targetName: 'Insert',
      hint: 'Shift+Insert → Insert'
    },

    'Home': {
      enabled: true,
      type: 'shift',
      code: 'Home',
      targetKeysym: 0xFF50,
      targetName: 'Home',
      hint: 'Shift+Home → Home'
    },

    'End': {
      enabled: true,
      type: 'shift',
      code: 'End',
      targetKeysym: 0xFF57,
      targetName: 'End',
      hint: 'Shift+End → End'
    },

    'PageUp': {
      enabled: true,
      type: 'shift',
      code: 'PageUp',
      targetKeysym: 0xFF55,
      targetName: 'PageUp',
      hint: 'Shift+PageUp → PageUp'
    },

    'PageDown': {
      enabled: true,
      type: 'shift',
      code: 'PageDown',
      targetKeysym: 0xFF56,
      targetName: 'PageDown',
      hint: 'Shift+PageDown → PageDown'
    },

    // ── 可以添加更多映射 ────────────────────────────────────────
    /*
    'F1': {
      enabled: false,
      type: 'shift',
      code: 'F1',
      targetKeysym: 0xFFBE,  // F1
      targetName: 'F1',
      hint: 'Shift+F1 → F1'
    },
    */
  };

  // ── 其他配置 ─────────────────────────────────────────────────────

  const CONFIG = {
    // 是否启用映射功能
    enabled: true,

    // 是否显示提示信息
    showHint: true,

    // 提示显示时长（毫秒），0 表示不自动消失
    hintDuration: 0,  // 改为 0，提示不会自动消失，需手动关闭或按 F10 重新显示

    // 是否在控制台输出详细日志
    debug: true,

    // 当前语言
    lang: currentLang,

    // 国际化文本
    i18n: t
  };

  // ═══════════════════════════════════════════════════════════════
  // 🔧 实现代码（通常不需要修改）
  // ═══════════════════════════════════════════════════════════════

  var rfb = null;

  // ── 日志函数 ─────────────────────────────────────────────────
  function log() {
    if (CONFIG.debug) {
      console.log.apply(console, ['[key-remap]'].concat(Array.prototype.slice.call(arguments)));
    }
  }

  // ── 获取 RFB 实例 ────────────────────────────────────────────
  function getRFB() {
    if (window.UI_imported && UI_imported.rfb) {
      return UI_imported.rfb;
    }
    var container = document.getElementById('noVNC_container');
    if (container && container._rfb) {
      return container._rfb;
    }
    var canvas = document.querySelector('#noVNC_container canvas');
    if (canvas && canvas._rfb) {
      return canvas._rfb;
    }
    return null;
  }

  // ── 发送单个按键到 VNC 服务器 ────────────────────────────────
  function sendKey(keysym, code, name) {
    rfb = getRFB();
    if (!rfb) {
      log('RFB not ready');
      return;
    }

    log('Sending:', name, '(keysym: 0x' + keysym.toString(16).toUpperCase() + ')');

    try {
      rfb.sendKey(keysym, code, true);   // keydown
      setTimeout(function () {
        rfb.sendKey(keysym, code, false);  // keyup
      }, 50);
    } catch (e) {
      log('❌ Error sending key:', e);
    }
  }

  // ── 发送组合键到 VNC 服务器 ───────────────────────────────────
  function sendKeyCombo(keys) {
    rfb = getRFB();
    if (!rfb) {
      log('RFB not ready');
      return;
    }

    log('Sending combo:', keys.join(' + '));

    try {
      // 按下所有键
      keys.forEach(function (key) {
        rfb.sendKey(key, key, true);
      });

      // 释放所有键
      setTimeout(function () {
        keys.forEach(function (key) {
          rfb.sendKey(key, key, false);
        });
      }, 50);
    } catch (e) {
      log('❌ Error sending combo:', e);
    }
  }

  // ── 获取按键的 keysym ─────────────────────────────────────────
  function getKeysym(keyName) {
    // 常用按键的 keysym 映射
    const keysyms = {
      'Ctrl_L': 0xFFE3,
      'Ctrl_R': 0xFFE4,
      'Alt_L': 0xFFE9,
      'Alt_R': 0xFFEA,
      'Shift_L': 0xFFE1,
      'Shift_R': 0xFFE2,
      'Meta_L': 0xFFE7,
      'Meta_R': 0xFFE8,
      'Delete': 0xFFFF,
      'Insert': 0xFF63,
      'Home': 0xFF50,
      'End': 0xFF57,
      'PageUp': 0xFF55,
      'PageDown': 0xFF56,
      'Tab': 0xFF09,
      'Escape': 0xFF1B,
      'Return': 0xFF0D,
      'BackSpace': 0xFF08
    };

    return keysyms[keyName] || null;
  }

  // ── 键盘事件处理 ─────────────────────────────────────────────
  function handleKeyDown(e) {
    if (!CONFIG.enabled) return;

    var code = e.code;
    var key = e.key;

    // 调试：记录所有按键事件（前100次）
    if (!handleKeyDown.callCount) handleKeyDown.callCount = 0;
    if (handleKeyDown.callCount < 100) {
      handleKeyDown.callCount++;
      log('🔑 Key pressed:', code, 'key:', key, 'shiftKey:', e.shiftKey);
    }

    // 查找匹配的映射
    var mapping = MAPPINGS[code] || MAPPINGS[key];

    if (!mapping || !mapping.enabled) {
      return;  // 没有匹配的映射
    }

    // 检查映射类型
    if (mapping.type === 'single') {
      // 单键映射：直接发送目标键
      log('🔑 Single key:', code, '→', mapping.targetName);

      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();

      if (mapping.isCombo && mapping.comboKeys) {
        // 组合键（如 Ctrl+Alt+Del）
        var keysyms = mapping.comboKeys.map(getKeysym);
        sendKeyCombo(keysyms);
      } else {
        // 普通单键
        sendKey(mapping.targetKeysym, mapping.code, mapping.targetName);
      }

      return false;

    } else if (mapping.type === 'special') {
      // 特殊功能键（如重新显示提示）
      log('🔧 Special key:', code, '→', mapping.action);

      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();

      if (mapping.action === 'showHints') {
        // 移除旧提示并显示新提示
        removeHint();
        showHint();
      }

      return false;

    } else if (mapping.type === 'shift') {
      // Shift 组合映射：需要按住 Shift
      if (e.shiftKey) {
        log('⌨️ Shift combo:', 'Shift+' + code, '→', mapping.targetName);

        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();

        sendKey(mapping.targetKeysym, mapping.code, mapping.targetName);

        return false;
      } else {
        // 没有按 Shift，忽略
        log('⚠️ Shift not pressed for:', code, '(use Shift+' + code + ')');
      }
    }
  }

  // ── 显示提示信息 ─────────────────────────────────────────────
  function showHint() {
    if (!CONFIG.showHint) return;

    // 先移除旧提示
    removeHint();

    // 收集所有启用的映射提示（使用国际化文本）
    var hints = [];
    for (var key in MAPPINGS) {
      if (MAPPINGS[key].enabled) {
        var mapping = MAPPINGS[key];
        // 优先使用国际化文本，否则使用 hint
        var hint = CONFIG.i18n.mappings[key] || mapping.hint;
        hints.push(hint);
      }
    }

    if (hints.length === 0) {
      return;
    }

    var hint = document.createElement('div');
    hint.id = 'key-remap-hint';
    hint.style.cssText = [
      'position: fixed',
      'bottom: 70px',
      'left: 50%',
      'transform: translateX(-50%)',
      'background: rgba(0, 0, 0, 0.92)',
      'color: #4CAF50',
      'padding: 20px 28px',
      'border-radius: 12px',
      'font-size: 14px',
      'font-family: "SF Mono", "Monaco", "Consolas", "Courier New", monospace',
      'z-index: 99999',
      'pointer-events: auto',
      'box-shadow: 0 8px 32px rgba(0,0,0,0.6)',
      'border: 2px solid #4CAF50',
      'max-width: 650px',
      'line-height: 1.8',
      'min-width: 300px'
    ].join(';');

    // 关闭按钮
    var closeBtn = document.createElement('button');
    closeBtn.innerHTML = '×';
    closeBtn.style.cssText = [
      'position: absolute',
      'top: 8px',
      'right: 12px',
      'background: transparent',
      'border: none',
      'color: #4CAF50',
      'font-size: 24px',
      'cursor: pointer',
      'padding: 0',
      'width: 30px',
      'height: 30px',
      'line-height: 30px'
    ].join(';');
    closeBtn.onclick = removeHint;
    hint.appendChild(closeBtn);

    // 提示内容
    var content = document.createElement('div');
    content.innerHTML = '<strong>' + CONFIG.i18n.hintTitle + '</strong><br><br>' +
                       hints.join('<br>') +
                       '<br><br><em style="color: #888; font-size: 12px;">' +
                       CONFIG.i18n.tipOr + ' F10 ' + CONFIG.i18n.btnShowHints + '</em>';
    hint.appendChild(content);

    document.body.appendChild(hint);

    // 如果设置了自动消失时间
    if (CONFIG.hintDuration > 0) {
      setTimeout(function () {
        hint.style.transition = 'opacity 1s ease-in-out';
        hint.style.opacity = '0';
        setTimeout(function () {
          removeHint();
        }, 1000);
      }, CONFIG.hintDuration);
    }

    log('💡 Hint displayed (lang: ' + currentLang + ')');
  }

  // ── 移除提示信息 ─────────────────────────────────────────────
  function removeHint() {
    var hint = document.getElementById('key-remap-hint');
    if (hint && hint.parentNode) {
      hint.parentNode.removeChild(hint);
      log('🗑️ Hint removed');
    }
  }

  // ── 增强 Extra Keys 面板 ───────────────────────────────────────
  function enhanceExtraKeysPanel() {
    var checkInterval = setInterval(function () {
      var escButton = document.getElementById('noVNC_send_esc_button');
      if (escButton) {
        clearInterval(checkInterval);

        // 收集单键映射的按键名
        var singleKeys = [];
        for (var key in MAPPINGS) {
          if (MAPPINGS[key].enabled && MAPPINGS[key].type === 'single') {
            singleKeys.push(key);
          }
        }

        if (singleKeys.length > 0) {
          var originalTitle = escButton.getAttribute('title') || 'Send Escape';
          escButton.setAttribute('title', originalTitle + ' (' + CONFIG.i18n.tipOr + ' ' + singleKeys.join(' / ') + ')');
        }

        log('✅ Enhanced Extra Keys panel');
      }
    }, 500);

    setTimeout(function () {
      clearInterval(checkInterval);
    }, 10000);

    // 添加"显示提示"按钮到控制栏
    var addHintButton = setInterval(function () {
      var controlBar = document.getElementById('noVNC_control_bar');
      if (controlBar && !document.getElementById('noVNC_show_hints_button')) {
        clearInterval(addHintButton);

        // 查找全屏按钮作为参考位置
        var fullscreenBtn = document.getElementById('noVNC_fullscreen_button');
        if (!fullscreenBtn) {
          log('⚠️ Fullscreen button not found, skipping hint button');
          return;
        }

        // 创建提示按钮
        var hintBtn = document.createElement('input');
        hintBtn.type = 'image';
        hintBtn.id = 'noVNC_show_hints_button';
        hintBtn.className = 'noVNC_button noVNC_hidden';
        hintBtn.alt = CONFIG.i18n.btnShowHints;
        hintBtn.title = CONFIG.i18n.btnShowHintsHint;
        hintBtn.src = 'app/images/info.svg';  // 使用 info 图标

        // 插入到全屏按钮后面
        fullscreenBtn.parentNode.insertBefore(hintBtn, fullscreenBtn.nextSibling);

        // 添加点击事件
        hintBtn.addEventListener('click', function() {
          removeHint();
          showHint();
        });

        // 显示按钮（移除 noVNC_hidden 类）
        hintBtn.classList.remove('noVNC_hidden');

        log('✅ Added hint button to control bar');
      }
    }, 1000);

    setTimeout(function () {
      clearInterval(addHintButton);
    }, 15000);
  }

  // ── 初始化 ───────────────────────────────────────────────────
  function init() {
    log('🚀 Initializing...');
    log('🌐 Language:', currentLang);
    log('📋 Enabled mappings:');

    for (var key in MAPPINGS) {
      if (MAPPINGS[key].enabled) {
        log('  -', MAPPINGS[key].hint);
      }
    }

    // 在多个地方添加键盘事件监听，确保捕获按键
    // 1. document 级别（capture phase，最高优先级）
    document.addEventListener('keydown', handleKeyDown, true);
    log('✓ Added keydown listener to document (capture phase)');

    // 2. window 级别
    window.addEventListener('keydown', handleKeyDown, true);
    log('✓ Added keydown listener to window (capture phase)');

    // 3. 尝试添加到 canvas（如果已存在）
    var canvas = document.querySelector('#noVNC_container canvas');
    if (canvas) {
      canvas.addEventListener('keydown', handleKeyDown, true);
      log('✓ Added keydown listener to canvas (capture phase)');
    } else {
      log('⚠️ Canvas not found yet, will retry...');
      // 延迟重试
      setTimeout(function() {
        var canvas2 = document.querySelector('#noVNC_container canvas');
        if (canvas2 && !canvas2.hasAttribute('data-key-remap-added')) {
          canvas2.addEventListener('keydown', handleKeyDown, true);
          canvas2.setAttribute('data-key-remap-added', 'true');
          log('✓ Added keydown listener to canvas (retry)');
        }
      }, 2000);
    }

    // 显示提示
    showHint();

    // 增强 Extra Keys 面板
    enhanceExtraKeysPanel();

    // 等待 UI 模块加载
    import('./app/ui.js').then(function(module) {
      log('✓ UI module imported');
      window.UI_imported = module.default;

      // UI 加载后再次尝试添加监听器
      setTimeout(function() {
        var canvas3 = document.querySelector('#noVNC_container canvas');
        if (canvas3 && !canvas3.hasAttribute('data-key-remap-added')) {
          canvas3.addEventListener('keydown', handleKeyDown, true);
          canvas3.setAttribute('data-key-remap-added', 'true');
          log('✓ Added keydown listener to canvas (after UI load)');
        }
      }, 1000);
    }).catch(function(e) {
      log('❌ UI import failed:', e.message);
    });

    log('✅ Key remapping enabled');
    log('💡 Try pressing Pause or ScrollLock key now');
  }

  // ── 启动 ─────────────────────────────────────────────────────
  function tryInit() {
    init();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      setTimeout(tryInit, 200);
    });
  } else {
    setTimeout(tryInit, 200);
  }

  // ── 暴露配置到全局，方便调试和动态修改 ────────────────────────
  window.KEY_REMAP_CONFIG = {
    MAPPINGS: MAPPINGS,
    CONFIG: CONFIG
  };

  log('📝 配置已暴露到全局变量 KEY_REMAP_CONFIG');
  log('💡 在控制台输入 KEY_REMAP_CONFIG.MAPPINGS 可查看所有映射');
  log('💡 修改后按 Ctrl+R 刷新页面生效');

})();

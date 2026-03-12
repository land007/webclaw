/**
 * audio-bar.js - integrated audio toggle button for noVNC
 *
 * Always shows in noVNC toolbar regardless of iframe environment.
 * If audioPort parameter is present in URL, auto-starts audio playback.
 * Audio control is now handled within noVNC itself.
 * Full-duplex: also includes a microphone button to send browser mic to container.
 */
(function () {
  'use strict';

  // ── i18n (Internationalization) ─────────────────────────────
  function getLanguage() {
    // Check browser language, default to 'en'
    var lang = navigator.language || navigator.userLanguage || 'en';
    // Return 'zh' for Chinese, 'en' for others
    return lang.toLowerCase().startsWith('zh') ? 'zh' : 'en';
  }

  var i18n = {
    en: {
      audioAlt: 'Audio',
      audioTitle: 'Desktop Audio',
      micAlt: 'Mic',
      micTitle: 'Microphone Input',
      recordAlt: 'Record',
      recordTitle: 'Record Desktop Video',
      stopRecordingTitle: 'Stop Recording'
    },
    zh: {
      audioAlt: '音频',
      audioTitle: '桌面音频',
      micAlt: '麦克风',
      micTitle: '麦克风输入',
      recordAlt: '录制',
      recordTitle: '录制桌面视频',
      stopRecordingTitle: '停止录制'
    }
  };

  var t = i18n[getLanguage()];
  console.log('[audio-bar] Language:', getLanguage());

  // ── SVG Icons (white) ─────────────────────────────────────
  function getIcon() {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"></path></svg>';
  }

  function getMicIcon() {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="9" y="2" width="6" height="11" rx="3"></rect>' +
      '<path d="M19 10a7 7 0 0 1-14 0"></path>' +
      '<line x1="12" y1="19" x2="12" y2="22"></line>' +
      '<line x1="8" y1="22" x2="16" y2="22"></line>' +
      '</svg>';
  }

  function getRecordIcon() {   // white circle = ready to record
    return '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24">' +
      '<circle cx="12" cy="12" r="7" fill="white" stroke="white" stroke-width="1.5"/></svg>';
  }

  function getRecordingIcon() {  // white square = recording (click to stop)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24">' +
      '<rect x="5" y="5" width="14" height="14" rx="2" fill="white" stroke="white" stroke-width="1.5"/></svg>';
  }

  // ── Audio WebSocket URL ───────────────────────────────────
  function getAudioWebSocketUrl() {
    // Use current page's protocol, host, and port with /audio path
    var protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    return protocol + '//' + location.host + '/audio';
  }

  var AUDIO_WS_URL = getAudioWebSocketUrl();
  console.log('[audio-bar] WebSocket URL:', AUDIO_WS_URL);

  // ── Check if should auto-start ─────────────────────────────
  // Auto-start if URL has autoconnect=true (noVNC parameter)
  function shouldAutoStart() {
    return location.search.match(/autoconnect=true/i) !== null;
  }

  // ── Create audio output button ────────────────────────────
  function createButton() {
    var fsBtn = document.getElementById('noVNC_fullscreen_button');
    if (!fsBtn) {
      console.log('[audio-bar] Fullscreen button not found');
      return false;
    }

    if (document.getElementById('noVNC_audio_button')) {
      console.log('[audio-bar] Button already exists');
      return true;
    }

    var btn = document.createElement('input');
    btn.type = 'image';
    btn.id = 'noVNC_audio_button';
    btn.className = 'noVNC_button';
    btn.alt = t.audioAlt;
    btn.title = t.audioTitle;
    btn.src = 'data:image/svg+xml;base64,' + btoa(getIcon());

    fsBtn.parentNode.insertBefore(btn, fsBtn);
    console.log('[audio-bar] ✅ Audio button created in noVNC toolbar');
    return true;
  }

  // ── Create microphone button (inserted after audio button) ──
  function createMicButton() {
    var audioBtn = document.getElementById('noVNC_audio_button');
    if (!audioBtn) return false;

    if (document.getElementById('noVNC_mic_button')) return true;

    var btn = document.createElement('input');
    btn.type = 'image';
    btn.id = 'noVNC_mic_button';
    btn.className = 'noVNC_button';
    btn.alt = t.micAlt;
    btn.title = t.micTitle;
    btn.src = 'data:image/svg+xml;base64,' + btoa(getMicIcon());

    audioBtn.parentNode.insertBefore(btn, audioBtn.nextSibling);
    console.log('[audio-bar] ✅ Mic button created in noVNC toolbar');
    return true;
  }

  // ── Create record button (inserted after mic button) ──────
  function createRecordButton() {
    var micBtn = document.getElementById('noVNC_mic_button');
    if (!micBtn) return false;

    if (document.getElementById('noVNC_record_button')) return true;

    var btn = document.createElement('input');
    btn.type = 'image';
    btn.id = 'noVNC_record_button';
    btn.className = 'noVNC_button';
    btn.alt = t.recordAlt;
    btn.title = t.recordTitle;
    btn.src = 'data:image/svg+xml;base64,' + btoa(getRecordIcon());

    micBtn.parentNode.insertBefore(btn, micBtn.nextSibling);
    console.log('[audio-bar] ✅ Record button created in noVNC toolbar');
    return true;
  }

  // ── Wait and create all three buttons ────────────────────
  function tryCreate() {
    var audioOk = createButton();
    if (!audioOk) {
      setTimeout(tryCreate, 100);
      return;
    }
    if (!createMicButton()) {
      setTimeout(tryCreate, 100);
      return;
    }
    if (!createRecordButton()) {
      setTimeout(tryCreate, 100);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', tryCreate);
  } else {
    setTimeout(tryCreate, 100);
  }

  // ── Audio output logic ───────────────────────────────────
  var audioCtx, ws, nextPlayTime = 0, active = false;
  var SAMPLE_RATE = 48000, CHANNELS = 2;  // 48000Hz = Opus native rate
  var autoStartAttempted = false;
  var recordActive = false;
  // Opus / WebCodecs state (output)
  var audioDecoder = null, opusFrameTimestamp = 0, codecOpus = false;
  var serverCodec = null;  // 'opus' | 'pcm' | null (null = waiting for codec_info)
  // Opus / WebCodecs state (microphone input)
  var micEncoder = null, micTimestamp = 0, codecOpusMic = false;
  // WebSocket connection reference counting (shared by audio output and mic input)
  var wsRefCount = 0;

  function setSelected(selected) {
    var btn = document.getElementById('noVNC_audio_button');
    if (!btn) return;
    if (selected) {
      btn.className = 'noVNC_button noVNC_selected';
    } else {
      btn.className = 'noVNC_button';
    }
  }

  function setRecordSelected(selected) {
    var btn = document.getElementById('noVNC_record_button');
    if (!btn) return;
    btn.className = selected ? 'noVNC_button noVNC_selected' : 'noVNC_button';
    btn.src = 'data:image/svg+xml;base64,' + btoa(selected ? getRecordingIcon() : getRecordIcon());
    btn.title = selected ? t.stopRecordingTitle : t.recordTitle;
  }

  function handleRecordingMessage(text) {
    var msg;
    try { msg = JSON.parse(text); } catch (e) { return; }
    if (msg.event === 'recording_started') {
      recordActive = true;
      setRecordSelected(true);
      console.log('[audio-bar] Recording started:', msg.filename);
    } else if (msg.event === 'recording_stopped') {
      recordActive = false;
      setRecordSelected(false);
      console.log('[audio-bar] Recording saved:', msg.filename);
    } else if (msg.event === 'recording_error') {
      recordActive = false;
      setRecordSelected(false);
      console.error('[audio-bar] Recording error:', msg.error);
    } else if (msg.event === 'recording_status') {
      recordActive = msg.recording;
      setRecordSelected(msg.recording);
    }
  }

  function stopAudio() {
    // Tell server to stop pushing audio to us
    if (ws && ws.readyState === WebSocket.OPEN) {
      try { ws.send(JSON.stringify({action: 'set_audio', enabled: false})); } catch (e) {}
    }
    active = false;
    setSelected(false);
    codecOpus = false;
    serverCodec = null;
    opusFrameTimestamp = 0;
    if (audioDecoder) {
      try { audioDecoder.close(); } catch (e) {}
      audioDecoder = null;
    }
    if (audioCtx) { audioCtx.close(); audioCtx = null; }

    // Decrement ref count and close connection if no one is using it
    wsRefCount--;
    if (wsRefCount <= 0) {
      if (ws) { ws.close(); ws = null; }
    }
  }

  function startAudio() {
    active = true;
    setSelected(true);

    try {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: SAMPLE_RATE });
    } catch (e) {
      console.error('[audio-bar]', e);
      stopAudio();
      return;
    }

    nextPlayTime = audioCtx.currentTime + 0.02;

    // Reuse existing WebSocket or create new one
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      console.log('[audio-bar] Connecting WebSocket:', AUDIO_WS_URL);
      try {
        ws = new WebSocket(AUDIO_WS_URL);
      } catch (e) {
        console.error('[audio-bar]', e);
        stopAudio();
        return;
      }

      ws.binaryType = 'arraybuffer';

      ws.onopen = function () {
        console.log('[audio-bar] ✅ WebSocket connected');
        // Tell server to start pushing audio, requesting PCM if AudioDecoder is unavailable
        if (active) {
          var preferPcm = !window.AudioDecoder;
          console.log('[audio-bar] prefer_pcm=' + preferPcm + ' (AudioDecoder available: ' + !!window.AudioDecoder + ')');
          try { ws.send(JSON.stringify({action: 'set_audio', enabled: true, prefer_pcm: preferPcm})); } catch (e) {}
        }
        // Query recording status
        try { ws.send(JSON.stringify({action: 'recording_status'})); } catch (e) {}
      };

      ws.onerror = function (e) {
        console.error('[audio-bar]', e);
        // Stop both audio and mic on error
        active = false;
        if (micActive) stopMicrophone();
      };

      ws.onclose = function () {
        wsRefCount = 0;
        // Stop both audio and mic on close
        if (active) stopAudio();
        if (micActive) stopMicrophone();
      };

      ws.onmessage = function (event) {
        if (typeof event.data === 'string') {
          var msg;
          try { msg = JSON.parse(event.data); } catch (e) { return; }
          if (msg.event === 'codec_info') {
            if (msg.codec === 'pcm') {
              serverCodec = 'pcm';
              console.log('[audio-bar] Server will send PCM (non-secure context mode)');
            } else if (msg.codec === 'opus') {
              serverCodec = 'opus';
              initOpusDecoder(msg);
            }
            return;
          }
          handleRecordingMessage(event.data);
          return;
        }
        if (!audioCtx) return;
        if (serverCodec === 'opus' && codecOpus && audioDecoder && audioDecoder.state === 'configured') {
          // ── Opus path (WebCodecs AudioDecoder) ──────────────────
          try {
            audioDecoder.decode(new EncodedAudioChunk({
              type: 'key',
              timestamp: opusFrameTimestamp,
              data: event.data,
            }));
            opusFrameTimestamp += 20000; // 20ms per frame in microseconds
          } catch (e) {
            console.error('[audio-bar] AudioDecoder.decode error:', e);
          }
        } else if (serverCodec === 'pcm') {
          // ── PCM path (server sent raw PCM, non-secure context) ──
          var pcmData = event.data;
          if (pcmData.byteLength % 2 !== 0) {
            pcmData = pcmData.slice(0, pcmData.byteLength - 1);  // align to 16-bit boundary
          }
          var raw = new Int16Array(pcmData);
          var numFrames = raw.length / CHANNELS;
          if (numFrames < 1) return;
          var buffer = audioCtx.createBuffer(CHANNELS, numFrames, SAMPLE_RATE);
          for (var ch = 0; ch < CHANNELS; ch++) {
            var channelData = buffer.getChannelData(ch);
            for (var i = 0; i < numFrames; i++) {
              channelData[i] = raw[i * CHANNELS + ch] / 32768.0;
            }
          }
          var source = audioCtx.createBufferSource();
          source.buffer = buffer;
          source.connect(audioCtx.destination);
          var now = audioCtx.currentTime;
          if (nextPlayTime < now) nextPlayTime = now + 0.01;
          source.start(nextPlayTime);
          nextPlayTime += buffer.duration;
        } else {
          // serverCodec === null or opus but AudioDecoder not ready → discard
          return;
        }
      };
    } else {
      // Reusing existing connection, just tell server to start pushing
      console.log('[audio-bar] Reusing existing WebSocket connection');
      try { ws.send(JSON.stringify({action: 'set_audio', enabled: true})); } catch (e) {}
    }

    wsRefCount++;
  }

  // ── Opus decoder via WebCodecs AudioDecoder ──────────────
  function initOpusDecoder(codecInfo) {
    if (!window.AudioDecoder) {
      console.warn('[audio-bar] AudioDecoder not available; Opus playback disabled');
      return;
    }
    var sr = codecInfo.sample_rate || 48000;
    var ch = codecInfo.channels || 2;
    console.log('[audio-bar] Initialising Opus decoder: ' + sr + 'Hz ' + ch + 'ch @ ' + codecInfo.bitrate + 'bps');

    if (audioDecoder) {
      try { audioDecoder.close(); } catch (e) {}
    }
    opusFrameTimestamp = 0;

    audioDecoder = new AudioDecoder({
      output: function (audioData) {
        if (!audioCtx) { audioData.close(); return; }
        var numFrames = audioData.numberOfFrames;
        var numChannels = audioData.numberOfChannels;
        var sampleRate = audioData.sampleRate;
        var buffer = audioCtx.createBuffer(numChannels, numFrames, sampleRate);
        for (var c = 0; c < numChannels; c++) {
          var plane = new Float32Array(numFrames);
          audioData.copyTo(plane, { planeIndex: c, format: 'f32-planar' });
          buffer.copyToChannel(plane, c);
        }
        audioData.close();
        var source = audioCtx.createBufferSource();
        source.buffer = buffer;
        source.connect(audioCtx.destination);
        var now = audioCtx.currentTime;
        if (nextPlayTime < now) nextPlayTime = now + 0.005; // 5ms resync
        source.start(nextPlayTime);
        nextPlayTime += buffer.duration;
      },
      error: function (e) {
        console.error('[audio-bar] AudioDecoder error:', e);
      },
    });

    audioDecoder.configure({ codec: 'opus', sampleRate: sr, numberOfChannels: ch });
    codecOpus = true;
    console.log('[audio-bar] ✅ Opus decoder ready');
  }

  // ── Microphone input logic ───────────────────────────────
  var micActive = false;
  var micStream = null;
  var micAudioCtx = null;
  var micProcessor = null;

  function setMicSelected(selected) {
    var btn = document.getElementById('noVNC_mic_button');
    if (!btn) return;
    btn.className = selected ? 'noVNC_button noVNC_selected' : 'noVNC_button';
  }

  function stopMicrophone() {
    micActive = false;
    codecOpusMic = false;
    micTimestamp = 0;
    if (micEncoder) {
      try { micEncoder.close(); } catch (e) {}
      micEncoder = null;
    }
    if (micProcessor) { micProcessor.disconnect(); micProcessor = null; }
    if (micStream) { micStream.getTracks().forEach(function(t) { t.stop(); }); micStream = null; }
    if (micAudioCtx) { micAudioCtx.close(); micAudioCtx = null; }

    // Decrement ref count and close connection if no one is using it
    wsRefCount--;
    if (wsRefCount <= 0) {
      if (ws) { ws.close(); ws = null; }
    }

    setMicSelected(false);
    console.log('[audio-bar] Microphone stopped');
  }

  // ── Opus encoder for microphone upload ────────────────────
  function initOpusEncoder() {
    if (!window.AudioEncoder) {
      console.warn('[audio-bar] AudioEncoder not available; mic upload will use raw PCM');
      return false;
    }
    console.log('[audio-bar] Initialising Opus encoder for mic upload: ' + SAMPLE_RATE + 'Hz ' + CHANNELS + 'ch');

    micTimestamp = 0;

    micEncoder = new AudioEncoder({
      output: function(encodedChunk) {
        if (ws && ws.readyState === WebSocket.OPEN) {
          try {
            // EncodedAudioChunk: use copyTo() to get ArrayBuffer
            var size = encodedChunk.byteLength;
            var buffer = new ArrayBuffer(size);
            encodedChunk.copyTo(buffer);
            ws.send(buffer);
          } catch (e) {
            console.error('[audio-bar] mic Opus send error:', e);
          }
        }
        // encodedChunk will be garbage-collected automatically
      },
      error: function(e) {
        console.error('[audio-bar] mic AudioEncoder error:', e);
      }
    });

    micEncoder.configure({
      codec: 'opus',
      sampleRate: SAMPLE_RATE,
      numberOfChannels: CHANNELS,
      bitrate: 64000  // 64 Kbps
    });
    codecOpusMic = true;
    console.log('[audio-bar] ✅ Opus encoder ready for mic');
    return true;
  }

  async function startMicrophone() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      console.warn('[audio-bar] getUserMedia not available in this environment');
      return;
    }

    try {
      micStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: { ideal: CHANNELS },
          sampleRate: { ideal: SAMPLE_RATE },
          echoCancellation: true,
          noiseSuppression: true,
        }
      });
    } catch (e) {
      console.error('[audio-bar] getUserMedia failed:', e);
      return;
    }

    micActive = true;
    setMicSelected(true);

    try {
      micAudioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: SAMPLE_RATE });
    } catch (e) {
      console.error('[audio-bar] AudioContext failed:', e);
      stopMicrophone();
      return;
    }

    // Try to initialise Opus encoder for upload compression
    var opusReady = initOpusEncoder();

    var source = micAudioCtx.createMediaStreamSource(micStream);
    // Use smaller buffer for lower latency (~21ms @ 48000Hz stereo)
    micProcessor = micAudioCtx.createScriptProcessor(2048, CHANNELS, CHANNELS);

    micProcessor.onaudioprocess = function(e) {
      if (!ws || ws.readyState !== WebSocket.OPEN) return;

      if (codecOpusMic && micEncoder && micEncoder.state === 'configured') {
        // ── Opus encoding path ───────────────────────────────
        var numFrames = e.inputBuffer.length;
        var numChannels = e.inputBuffer.numberOfChannels;

        // Interleave channels into single Float32Array (format: 'f32')
        var interleaved = new Float32Array(numFrames * numChannels);
        for (var ch = 0; ch < numChannels; ch++) {
          var channelData = e.inputBuffer.getChannelData(ch);
          for (var i = 0; i < numFrames; i++) {
            interleaved[i * numChannels + ch] = channelData[i];
          }
        }

        try {
          var audioData = new AudioData({
            format: 'f32',  // interleaved float32
            sampleRate: SAMPLE_RATE,
            numberOfFrames: numFrames,
            numberOfChannels: numChannels,
            timestamp: micTimestamp,
            data: interleaved
          });
          micEncoder.encode(audioData);
          micTimestamp += Math.floor(numFrames * 1000000 / SAMPLE_RATE);  // microseconds
          // audioData will be garbage-collected automatically
        } catch (err) {
          console.error('[audio-bar] mic encode error:', err);
        }
      } else {
        // ── Fallback: raw PCM Int16 ─────────────────────────────
        var numFrames = e.inputBuffer.length;
        var buf = new Int16Array(numFrames * CHANNELS);
        for (var ch = 0; ch < CHANNELS; ch++) {
          var channelData = e.inputBuffer.getChannelData(ch);
          for (var i = 0; i < numFrames; i++) {
            var sample = Math.max(-1, Math.min(1, channelData[i]));
            buf[i * CHANNELS + ch] = sample < 0 ? sample * 32768 : sample * 32767;
          }
        }
        ws.send(buf.buffer);
      }
    };

    source.connect(micProcessor);
    micProcessor.connect(micAudioCtx.destination);

    // Reuse existing WebSocket or create new one
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      console.log('[audio-bar] Creating WebSocket for mic:', AUDIO_WS_URL);
      try {
        ws = new WebSocket(AUDIO_WS_URL);
      } catch (e) {
        console.error('[audio-bar] WebSocket failed:', e);
        stopMicrophone();
        return;
      }

      ws.binaryType = 'arraybuffer';

      ws.onopen = function () {
        console.log('[audio-bar] ✅ WebSocket connected (for mic)');
        // Tell server we support Opus upload
        if (codecOpusMic) {
          try {
            ws.send(JSON.stringify({
              action: 'mic_codec',
              codec: 'opus',
              sample_rate: SAMPLE_RATE,
              channels: CHANNELS,
              bitrate: 64000
            }));
            console.log('[audio-bar] ✅ Mic Opus codec announced to server');
          } catch (e) {
            console.error('[audio-bar] mic codec announcement failed:', e);
          }
        }
      };

      ws.onerror = function (e) {
        console.error('[audio-bar] WebSocket error:', e);
        // Stop both audio and mic on error
        if (active) stopAudio();
        if (micActive) stopMicrophone();
      };

      ws.onclose = function () {
        wsRefCount = 0;
        // Stop both audio and mic on close
        if (active) stopAudio();
        if (micActive) stopMicrophone();
      };

      // onmessage handler is already set in startAudio(), will be reused
      ws.onmessage = ws.onmessage || function (event) {
        if (typeof event.data === 'string') {
          var msg;
          try { msg = JSON.parse(event.data); } catch (e) { return; }
          if (msg.event === 'codec_info') {
            if (active) initOpusDecoder(msg);
            return;
          }
          handleRecordingMessage(event.data);
          return;
        }
        // Audio data handling is in the shared ws.onmessage from startAudio()
      };
    } else {
      // Reusing existing connection, just announce codec
      console.log('[audio-bar] Reusing existing WebSocket for mic');
      if (codecOpusMic) {
        try {
          ws.send(JSON.stringify({
            action: 'mic_codec',
            codec: 'opus',
            sample_rate: SAMPLE_RATE,
            channels: CHANNELS,
            bitrate: 64000
          }));
          console.log('[audio-bar] ✅ Mic Opus codec announced to server');
        } catch (e) {
          console.error('[audio-bar] mic codec announcement failed:', e);
        }
      }
    }

    wsRefCount++;
    console.log('[audio-bar] ✅ Microphone started (Opus 64kbps)');
  }

  // ── Click handlers ────────────────────────────────────────
  document.addEventListener('click', function(e) {
    if (e.target && e.target.id === 'noVNC_audio_button') {
      e.preventDefault();
      console.log('[audio-bar] Audio button clicked, active:', active);
      if (active) stopAudio(); else startAudio();
    }
    if (e.target && e.target.id === 'noVNC_mic_button') {
      e.preventDefault();
      console.log('[audio-bar] Mic button clicked, active:', micActive);
      if (micActive) stopMicrophone(); else startMicrophone();
    }
    if (e.target && e.target.id === 'noVNC_record_button') {
      e.preventDefault();
      console.log('[audio-bar] Record button clicked, recordActive:', recordActive);
      if (!ws || ws.readyState !== WebSocket.OPEN) {
        startAudio();  // establish WS connection first
        return;
      }
      ws.send(JSON.stringify({action: recordActive ? 'stop_recording' : 'start_recording'}));
    }
  }, true);

  // ── Auto-start audio if audioPort parameter exists ──────────
  // Note: AudioContext requires user gesture, so we wait for first interaction
  function attemptAutoStart() {
    if (autoStartAttempted || !shouldAutoStart()) return;
    autoStartAttempted = true;

    console.log('[audio-bar] Auto-start requested, waiting for user gesture...');

    // Wait for any user interaction (click, keypress, touch)
    function onUserGesture() {
      if (!active && shouldAutoStart()) {
        console.log('[audio-bar] User gesture detected, starting audio...');
        startAudio();
      }
      // Remove listeners after first interaction
      document.removeEventListener('click', onUserGesture, true);
      document.removeEventListener('keydown', onUserGesture, true);
      document.removeEventListener('touchstart', onUserGesture, true);
    }

    document.addEventListener('click', onUserGesture, true);
    document.addEventListener('keydown', onUserGesture, true);
    document.addEventListener('touchstart', onUserGesture, true);
  }

  // Try auto-start after button is created
  function tryAutoStart() {
    if (document.getElementById('noVNC_audio_button')) {
      attemptAutoStart();
    } else {
      setTimeout(tryAutoStart, 100);
    }
  }

  if (shouldAutoStart()) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', tryAutoStart);
    } else {
      setTimeout(tryAutoStart, 100);
    }
  }
})();

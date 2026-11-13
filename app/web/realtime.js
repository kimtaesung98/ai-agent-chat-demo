// OpenAI GPT Realtime WebRTC 연결 (SPEC.md F-024, ARCHITECTURE.md ADR-026).
// Dart(lib/voice/openai_realtime_agent.dart)가 dart:js_interop으로 window.aiRealtime을 부른다.
// 브라우저는 서버(API-007)가 준 임시 키만 쓴다 — API 키·지시문은 여기에 없다.
// 대화 내용은 콘솔에 남기지 않는다.
(function () {
  'use strict';
  const CALLS_URL = 'https://api.openai.com/v1/realtime/calls';
  let pc = null, dc = null, mic = null, audio = null, levelTimer = null, ctx = null;
  let emit = function () {};
  let userText = '', replyText = '', replyHeld = null, userPending = false, holdTimer = null;

  function send(type, text) {
    try { emit(type, text == null ? '' : String(text)); } catch (_) {}
  }

  // 사용자 말 전사는 답보다 늦게 올 수 있다. 내역 순서를 지키려고 답을 잠깐 붙잡아 둔다.
  function flushReply() {
    if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
    if (replyHeld != null) { const t = replyHeld; replyHeld = null; send('reply', t); }
  }
  function reply(text) {
    if (!text) return;
    if (userPending) {
      replyHeld = replyHeld ? replyHeld + ' ' + text : text;
      if (!holdTimer) holdTimer = setTimeout(function () { userPending = false; flushReply(); }, 3000);
    } else {
      send('reply', text);
    }
  }

  function onServerEvent(e) {
    let m;
    try { m = JSON.parse(e.data); } catch (_) { return; }
    switch (m.type) {
      case 'input_audio_buffer.speech_started':
        userText = '';
        send('user_speaking');
        break;
      case 'input_audio_buffer.committed':
        userPending = true;
        break;
      case 'conversation.item.input_audio_transcription.delta':
        userText += m.delta || '';
        send('heard_partial', userText);
        break;
      case 'conversation.item.input_audio_transcription.completed':
        userPending = false;
        userText = '';
        if ((m.transcript || '').trim()) send('heard', m.transcript.trim());
        flushReply();
        break;
      case 'conversation.item.input_audio_transcription.failed':
        userPending = false;
        flushReply();
        break;
      case 'output_audio_buffer.started':
        send('speaking');
        break;
      case 'output_audio_buffer.stopped':
      case 'output_audio_buffer.cleared':
        send('listening');
        break;
      case 'response.output_audio_transcript.delta':
      case 'response.audio_transcript.delta':
        replyText += m.delta || '';
        send('reply_partial', replyText);
        break;
      case 'response.output_audio_transcript.done':
      case 'response.audio_transcript.done':
        replyText = '';
        reply((m.transcript || '').trim());
        break;
      case 'response.done':
        // 끼어들기로 잘리면 transcript.done 없이 끝날 수 있다 — 말한 데까지 남긴다
        if (replyText.trim()) { reply(replyText.trim()); }
        replyText = '';
        break;
      case 'error':
        console.warn('실시간 음성 오류', m.error && m.error.code);
        send('error');
        break;
    }
  }

  function startLevel(stream) {
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      ctx = new AC();
      const an = ctx.createAnalyser();
      an.fftSize = 512;
      ctx.createMediaStreamSource(stream).connect(an);
      const buf = new Uint8Array(an.fftSize);
      levelTimer = setInterval(function () {
        an.getByteTimeDomainData(buf);
        let sum = 0;
        for (let i = 0; i < buf.length; i++) { const v = (buf[i] - 128) / 128; sum += v * v; }
        send('level', Math.min(1, Math.sqrt(sum / buf.length) * 4).toFixed(3));
      }, 70);
    } catch (_) {}
  }

  function cleanup() {
    if (levelTimer) { clearInterval(levelTimer); levelTimer = null; }
    if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
    try { ctx && ctx.close(); } catch (_) {}
    try { dc && dc.close(); } catch (_) {}
    try { pc && pc.close(); } catch (_) {}
    if (mic) mic.getTracks().forEach(function (t) { t.stop(); });
    if (audio) { audio.srcObject = null; audio.remove(); }
    pc = dc = mic = audio = ctx = null;
    userText = replyText = ''; replyHeld = null; userPending = false;
  }

  window.aiRealtime = {
    supported: function () {
      return !!(window.RTCPeerConnection && navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
    },

    // secret: API-007 임시 키. greet: 처음 연결이면 에이전트가 먼저 인사한다.
    // onEvent(type, text): connected · disconnected · user_speaking · heard_partial · heard ·
    //   speaking · listening · reply_partial · reply · level · error · mic_denied
    start: async function (secret, greet, onEvent) {
      cleanup();
      emit = onEvent;
      const mine = (pc = new RTCPeerConnection());
      audio = document.createElement('audio');
      audio.autoplay = true;
      audio.setAttribute('playsinline', '');
      document.body.appendChild(audio);
      mine.ontrack = function (e) {
        audio.srcObject = e.streams[0];
        const p = audio.play();
        if (p && p.catch) p.catch(function () {});
      };
      mine.onconnectionstatechange = function () {
        if (pc !== mine) return;
        const s = mine.connectionState;
        if (s === 'failed' || s === 'disconnected' || s === 'closed') send('disconnected');
      };
      try {
        mic = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
        });
      } catch (err) {
        cleanup();
        if (err && (err.name === 'NotAllowedError' || err.name === 'SecurityError')) { send('mic_denied'); return; }
        throw err;
      }
      if (pc !== mine) { mic.getTracks().forEach(function (t) { t.stop(); }); return; }
      mic.getTracks().forEach(function (t) { mine.addTrack(t, mic); });
      startLevel(mic);
      dc = mine.createDataChannel('oai-events');
      dc.onmessage = onServerEvent;
      dc.onopen = function () {
        send('connected');
        if (greet) dc.send(JSON.stringify({ type: 'response.create' }));
      };
      const offer = await mine.createOffer();
      await mine.setLocalDescription(offer);
      const res = await fetch(CALLS_URL, {
        method: 'POST',
        body: offer.sdp,
        headers: { Authorization: 'Bearer ' + secret, 'Content-Type': 'application/sdp' },
      });
      if (!res.ok) { cleanup(); throw new Error('realtime ' + res.status); }
      const answer = await res.text();
      if (pc !== mine) return;
      await mine.setRemoteDescription({ type: 'answer', sdp: answer });
    },

    stop: function () { cleanup(); },

    setMuted: function (muted) {
      if (mic) mic.getAudioTracks().forEach(function (t) { t.enabled = !muted; });
    },
  };
})();

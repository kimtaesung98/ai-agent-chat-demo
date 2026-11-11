/// `speech_to_text` · `flutter_tts` 패키지로 만든 [VoiceEngine] (ARCHITECTURE.md ADR-014).
/// 두 패키지는 이 파일에서만 import한다. 웹에서는 브라우저 Web Speech API를, 모바일에서는 OS 음성 엔진을 쓴다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_engine.dart';

class PluginVoiceEngine implements VoiceEngine {
  PluginVoiceEngine({this.locale = 'ko-KR', this.pauseFor = const Duration(milliseconds: 1200)});

  /// 인식·합성 언어.
  final String locale;

  /// 이만큼 조용하면 말이 끝난 것으로 보고 문장을 확정한다 (자동 전송 시점).
  final Duration pauseFor;

  // 플러그인은 처음 쓸 때 만든다 — 생성자가 Flutter 바인딩(메서드 채널)을 쓰므로 runApp 전에 만들면 안 된다
  late final _stt = SpeechToText();
  late final _tts = FlutterTts();
  final _heard = StreamController<Heard>.broadcast();

  Future<bool>? _preparing;
  var _sttReady = false;
  var _ttsReady = false;
  var _voicePicked = false;

  var _want = false; // 음성 모드가 듣기를 원함
  var _session = false; // 듣기 세션이 열려 있음 (끝남 알림 전까지)
  var _finalSent = false; // 이번 세션에서 확정 문장을 보냈는지

  Completer<void>? _speaking;

  @override
  bool get canListen => _sttReady;
  @override
  bool get canSpeak => _ttsReady;
  @override
  Stream<Heard> get heard => _heard.stream;

  @override
  Future<bool> prepare() => _preparing ??= _prepare();

  Future<bool> _prepare() async {
    try {
      _sttReady = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        // 웹 구현은 결과를 항상 '중간'으로 주고, 멈춘 뒤 finalTimeout이 지나야 마지막 결과를 확정한다.
        // 기본 2초를 기다리면 답이 그만큼 늦으므로 웹에서는 짧게 (모바일은 OS가 확정 결과를 준다).
        finalTimeout: kIsWeb ? const Duration(milliseconds: 150) : SpeechToText.defaultFinalTimeout,
      );
    } catch (_) {
      _sttReady = false;
    }
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS: 음성 인식이 마이크를 잡고 있어도 답을 수화기가 아닌 스피커로 읽고(끼어들기용으로 듣기와 함께),
        // 블루투스 이어폰도 쓰게 한다 (F-017 AC4). 앱 전체가 하나의 오디오 세션을 쓴다.
        await _tts.setSharedInstance(true);
        await _tts.autoStopSharedSession(false); // 읽기가 끝나도 오디오 세션을 닫지 않는다 — 듣기가 이어진다
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ], IosTextToSpeechAudioMode.voicePrompt);
      }
      await _tts.awaitSpeakCompletion(false); // 완료는 아래 핸들러로 직접 받는다 (웹에서 취소 시 future가 끝나지 않음)
      _tts
        ..setCompletionHandler(_speechEnded)
        ..setCancelHandler(_speechEnded)
        ..setErrorHandler((_) => _speechEnded());
      await _tts.setLanguage(locale);
      await _pickVoice();
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
    if (!_sttReady) _preparing = null; // 다음에 다시 시도 (예: 권한을 나중에 허용)
    return _sttReady && _ttsReady;
  }

  /// 가장 자연스러운 한국어 목소리를 고른다: 이름에 Natural → Online → Google 순서로.
  Future<void> _pickVoice() async {
    if (_voicePicked) return;
    final voices = await _tts.getVoices;
    if (voices is! List || voices.isEmpty) return; // 크롬은 목소리 목록을 늦게 준다 — 첫 읽기에서 다시 시도
    final lang = locale.split('-').first.toLowerCase();
    final candidates = [
      for (final v in voices)
        if (v is Map && '${v['locale']}'.toLowerCase().startsWith(lang)) v,
    ];
    if (candidates.isEmpty) return;
    int rank(Map v) {
      final name = '${v['name']}';
      if (name.contains('Natural')) return 0;
      if (name.contains('Online')) return 1;
      if (name.contains('Google')) return 2;
      return 3;
    }

    candidates.sort((a, b) => rank(a).compareTo(rank(b)));
    final best = candidates.first;
    await _tts.setVoice({'name': '${best['name']}', 'locale': '${best['locale']}'});
    _voicePicked = true;
  }

  @override
  void startListening() {
    if (!_sttReady) return;
    _want = true;
    if (_session) return; // 지금 세션이 끝나면 _onStatus에서 다시 연다
    unawaited(_listen());
  }

  Future<void> _listen() async {
    _session = true;
    _finalSent = false;
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          listenMode: ListenMode.dictation,
          pauseFor: pauseFor,
          listenFor: const Duration(minutes: 1),
        ),
      );
    } catch (_) {
      _session = false;
      _want = false;
      _heard.add(const ListenFailed(ListenFailure.other));
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    final text = r.recognizedWords.trim();
    if (text.isEmpty) return;
    if (r.finalResult) {
      if (_finalSent) return;
      _finalSent = true;
      _heard.add(HeardFinal(text));
    } else {
      _heard.add(HeardPartial(text));
    }
  }

  void _onStatus(String status) {
    if (status != SpeechToText.doneStatus && status != 'doneNoResult') return;
    _session = false;
    if (!_want) return;
    if (!_finalSent) _heard.add(const ListenEnded());
    // 아직 원하면 새 세션을 연다. 플러그인의 상태 알림 안에서 바로 listen을 부르면 웹 구현이 알림을 마친 뒤
    // "끝남 보냄" 표시를 새 세션에 남겨, 새 세션이 끝나도 알림이 오지 않는다 → 다음 차례에 연다.
    Timer.run(() {
      if (_want && !_session) unawaited(_listen());
    });
  }

  void _onError(SpeechRecognitionError e) {
    final reason = switch (e.errorMsg) {
      'not-allowed' || 'service-not-allowed' || 'error_permission' => ListenFailure.notAllowed,
      'audio-capture' || 'error_audio' || 'error_audio_error' => ListenFailure.noMicrophone,
      'network' || 'error_network' || 'error_network_timeout' || 'error_server' => ListenFailure.network,
      // 조용함·인식 실패·우리가 멈춤은 오류가 아니다 — 세션 끝 알림에서 다시 듣는다
      'no-speech' || 'aborted' || 'error_no_match' || 'error_speech_timeout' || 'error_busy' => null,
      _ => e.permanent ? ListenFailure.other : null,
    };
    if (reason == null || !_want) return;
    _want = false;
    _heard.add(ListenFailed(reason));
  }

  @override
  void stopListening() {
    _want = false;
    if (_session) unawaited(_stt.cancel());
    _session = false;
  }

  @override
  Future<void> speak(String sentence) async {
    final previous = _speaking;
    if (previous != null) await previous.future; // 한 번에 한 문장
    if (!_voicePicked) await _pickVoice();
    final done = _speaking = Completer<void>();
    try {
      await _tts.speak(sentence);
    } catch (_) {
      _speechEnded();
    }
    return done.future;
  }

  void _speechEnded() {
    final c = _speaking;
    _speaking = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  void cancelSpeech() {
    _speechEnded();
    if (_ttsReady) unawaited(_tts.stop());
  }

  @override
  void dispose() {
    stopListening();
    cancelSpeech();
    unawaited(_heard.close());
  }
}

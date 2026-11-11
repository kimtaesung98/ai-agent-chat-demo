/// 음성 대화 진행 (SPEC.md F-012, ARCHITECTURE.md §5.3).
/// 듣기 → 말이 멈추면 자동 전송 → 답을 문장마다 바로 읽기 → 다 읽으면 다시 듣기, 읽는 중 끼어들기.
/// `package:flutter/foundation.dart`까지만 import한다 — 위젯 없이 가짜 엔진으로 단위 테스트한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chat/chat_controller.dart';
import 'sentences.dart';
import 'voice_engine.dart';

enum VoiceState {
  /// 음성 모드 꺼짐
  off,

  /// 사용자 말을 듣는 중
  listening,

  /// 질문을 보냈고 첫 문장을 기다리는 중
  thinking,

  /// 답을 읽는 중
  speaking,
}

/// 화면에 보여 줄 음성 안내 문장.
/// 미지원·권한 안내는 웹(브라우저)과 모바일 앱(OS 설정)에서 다르게 말한다 (F-017 AC4).
abstract final class VoiceMessages {
  static const unsupportedWeb = '이 브라우저는 음성 인식을 지원하지 않아요. Chrome이나 Edge에서 써 주세요.';
  static const unsupportedApp = '이 기기에서는 음성 인식을 쓸 수 없어요. 기기 설정에서 음성 인식 서비스를 확인해 주세요.';
  static const notAllowedWeb = '마이크 권한이 필요해요. 브라우저 주소창에서 마이크를 허용해 주세요.';
  static const notAllowedApp = '마이크·음성 인식 권한이 필요해요. 기기 설정 > 앱에서 권한을 허용해 주세요.';
  static String get unsupported => kIsWeb ? unsupportedWeb : unsupportedApp;
  static String get notAllowed => kIsWeb ? notAllowedWeb : notAllowedApp;
  static const noMicrophone = '마이크를 찾을 수 없어요.';
  static const network = '음성 인식 서비스에 연결할 수 없어요. 네트워크를 확인해 주세요.';
  static const failed = '음성 인식이 멈췄어요. 마이크 버튼을 다시 눌러 주세요.';
}

class VoiceController extends ChangeNotifier {
  VoiceController(this._chat, this._engine) {
    _heardSub = _engine.heard.listen(_onHeard);
    _chat.addListener(_onChat);
  }

  final ChatController _chat;
  final VoiceEngine _engine;
  late final StreamSubscription<Heard> _heardSub;
  final _splitter = SentenceSplitter();
  final _queue = <String>[];
  final _spoken = <String>[]; // 이번 답에서 읽었거나 읽는 중인 문장 (에코 판별)

  VoiceState _state = VoiceState.off;
  String _partial = '';
  String? _notice;
  ChatEntry? _answer; // 음성으로 보낸 질문의 답 말풍선
  var _answerDone = false;
  var _gen = 0; // 읽기 세대 — 끼어들기·끄기 때마다 늘려 이전 읽기 결과를 무시한다
  var _speakingNow = false;
  var _disposed = false;

  VoiceState get state => _state;
  bool get active => _state != VoiceState.off;

  /// 인식 중인 문장 (미리 보기).
  String get partial => _partial;

  /// 미지원·권한 거부 등 안내 (F-012 AC7). 없으면 null.
  String? get notice => _notice;

  bool get supported => _engine.canListen && _engine.canSpeak;

  /// 마이크 버튼: 꺼짐 → 켜기, 듣는 중 → 끄기, 생각·읽는 중 → 끼어들기 (F-012 AC5).
  void toggle() {
    switch (_state) {
      case VoiceState.off:
        unawaited(start());
      case VoiceState.listening:
        stop();
      case VoiceState.thinking || VoiceState.speaking:
        _bargeIn();
    }
  }

  var _starting = false;

  /// 음성 모드를 켜고 듣기 시작한다.
  Future<void> start() async {
    if (_state != VoiceState.off || _starting) return;
    _starting = true;
    final ok = await _engine.prepare();
    _starting = false;
    if (_disposed || _state != VoiceState.off) return;
    if (!ok || !supported) {
      _notice = VoiceMessages.unsupported;
      _notify();
      return;
    }
    _notice = null;
    _state = VoiceState.listening;
    _engine.startListening();
    _notify();
  }

  /// 음성 모드를 끈다: 듣기·읽기·진행 중인 요청을 모두 멈춘다 (F-012 AC4).
  void stop() {
    if (_state == VoiceState.off) return;
    _silence();
    _engine.stopListening();
    final answer = _answer;
    _answer = null; // 먼저 비워야 _chat.stop()의 알림이 다시 듣기를 시작하지 않는다
    if (answer != null && _chat.busy) _chat.stop();
    _partial = '';
    _state = VoiceState.off;
    _notify();
  }

  void _onHeard(Heard h) {
    if (_state == VoiceState.off) return;
    switch (h) {
      case HeardPartial(:final text):
        if (_state != VoiceState.listening) {
          if (_isEcho(text)) return; // 스피커 소리를 다시 들은 것 (R-A09)
          _bargeIn(listen: false);
        }
        _partial = text;
        _notify();
      case HeardFinal(:final text):
        if (_state != VoiceState.listening) {
          if (_isEcho(text)) {
            _engine.startListening();
            return;
          }
          _bargeIn(listen: false);
        }
        _partial = '';
        _send(text);
      case ListenEnded():
        _engine.startListening(); // 음성 모드인 동안은 계속 듣는다 (읽는 중에도 — 끼어들기)
      case ListenFailed(:final reason):
        final notice = switch (reason) {
          ListenFailure.notAllowed => VoiceMessages.notAllowed,
          ListenFailure.noMicrophone => VoiceMessages.noMicrophone,
          ListenFailure.network => VoiceMessages.network,
          ListenFailure.other => VoiceMessages.failed,
        };
        stop();
        _notice = notice;
        _notify();
    }
  }

  void _send(String text) {
    if (_chat.busy) _chat.stop();
    if (!_chat.send(text, voice: true)) {
      _engine.startListening();
      _notify();
      return;
    }
    _answer = _chat.entries.last;
    _answerDone = false;
    _splitter.reset();
    _spoken.clear();
    _state = VoiceState.thinking;
    _engine.startListening(); // 생각·읽는 중에도 듣는다 — 끼어들기
    _notify();
  }

  /// 답 말풍선이 바뀔 때마다 완성된 문장을 읽기 대기열에 넣는다 (F-012 AC2).
  void _onChat() {
    final answer = _answer;
    if (answer == null || _answerDone) return;
    switch (answer.status) {
      case EntryStatus.streaming:
        _enqueue(_splitter.push(answer.text));
      case EntryStatus.done:
        _answerDone = true;
        _enqueue(_splitter.push(answer.text));
        _enqueue(_splitter.flush());
        if (!_speakingNow && _queue.isEmpty) _backToListening();
      case EntryStatus.error:
        _answerDone = true;
        _silence();
        _enqueue([answer.text]); // 사용자용 오류 문장을 읽어 준다
      case EntryStatus.stopped:
        _answerDone = true;
        _silence();
        _backToListening();
    }
  }

  void _enqueue(List<String> sentences) {
    if (sentences.isEmpty) return;
    _queue.addAll(sentences);
    if (!_speakingNow) unawaited(_speakNext(_gen));
  }

  Future<void> _speakNext(int gen) async {
    _speakingNow = true;
    while (_queue.isNotEmpty && gen == _gen && !_disposed) {
      final s = _queue.removeAt(0);
      _spoken.add(s);
      if (_state != VoiceState.speaking) {
        _state = VoiceState.speaking;
        _notify();
      }
      await _engine.speak(s);
    }
    if (gen != _gen || _disposed) return; // 끼어들기·끄기가 이미 상태를 정리했다
    _speakingNow = false;
    if (_answerDone) {
      _backToListening(); // 다 읽음 → 다시 듣기 (F-012 AC4)
    } else {
      _state = VoiceState.thinking; // 다음 문장을 기다린다
      _notify();
    }
  }

  void _backToListening() {
    _answer = null;
    _state = VoiceState.listening;
    _engine.startListening();
    _notify();
  }

  /// 읽기를 멈추고 응답을 중단한 뒤 듣기로 (F-012 AC5). 받은 답은 "중단됨"으로 남는다 (F-003).
  void _bargeIn({bool listen = true}) {
    _silence();
    final answer = _answer;
    _answer = null;
    if (answer != null && answer.status == EntryStatus.streaming && _chat.busy) _chat.stop();
    _state = VoiceState.listening;
    if (listen) _engine.startListening();
    _notify();
  }

  void _silence() {
    _gen++;
    _queue.clear();
    _speakingNow = false;
    _engine.cancelSpeech();
  }

  /// 들은 문장이 방금 읽은 답과 비슷하면 스피커 소리가 마이크로 들어온 것으로 본다 (R-A09).
  bool _isEcho(String heard) {
    final h = _normalize(heard);
    if (h.length < 2) return true; // 한 글자는 잡음으로 본다
    final spoken = _normalize(_spoken.join());
    if (spoken.isEmpty) return false;
    if (spoken.contains(h)) return true;
    final hb = _bigrams(h);
    if (hb.isEmpty) return false;
    final sb = _bigrams(spoken);
    final common = hb.where(sb.contains).length;
    return common / hb.length >= 0.6;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _chat.removeListener(_onChat);
    unawaited(_heardSub.cancel());
    _engine
      ..cancelSpeech()
      ..stopListening();
    super.dispose();
  }
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);
String _normalize(String s) => s.toLowerCase().replaceAll(_nonWord, '');
Set<String> _bigrams(String s) => {for (var i = 0; i + 1 < s.length; i++) s.substring(i, i + 2)};

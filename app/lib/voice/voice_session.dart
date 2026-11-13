/// 음성 대화 화면(S-003)·채팅 화면 마이크가 보는 음성 대화의 모양 (SPEC.md F-018·F-024).
/// 구현은 [AgentVoiceController](OpenAI Realtime). `package:flutter/foundation.dart`까지만 import한다.
library;

import 'package:flutter/foundation.dart';

enum VoiceState {
  /// 음성 대화 꺼짐
  off,

  /// 사용자 말을 듣는 중
  listening,

  /// 연결 중이거나 답을 기다리는 중
  thinking,

  /// 답을 말하는 중
  speaking,
}

abstract interface class VoiceSession implements Listenable {
  VoiceState get state;
  bool get active;

  /// 인식 중인 사용자 말 (미리 보기).
  String get partial;

  /// 지금 말하는 답 (자막). 말하는 중이 아니면 빈 문자열.
  String get sentence;
  String? get notice;

  /// 마이크 소리 크기 0~1 — 음성 화면 파형 (F-018 AC11). 모르면 늘 0.
  ValueListenable<double> get level;
  bool get supported;
  void toggle();
  void tap();
  Future<void> start();
  void stop();
  void pause();
  void resume();
}

/// 소리 크기를 모를 때 쓰는 늘 0인 값.
final ValueListenable<double> silentLevel = ValueNotifier(0);

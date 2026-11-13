/// 마이크 소리 크기(dB)를 0~1로 바꾼다 (음성 화면 파형, F-018 AC11).
/// 기기마다 dB 범위가 다르다 (iOS는 대략 -50~0, Android는 -2~10) — 고정 범위 대신 지금까지 들은
/// 가장 조용한 소리와 가장 큰 소리 사이로 맞춘다. 두 끝은 천천히 안쪽으로 돌아와 방이 바뀌어도 따라간다.
library;

import 'dart:math' as math;

class LevelMeter {
  LevelMeter({this.minSpan = 10, this.drift = 0.05});

  /// 가장 조용한 소리와 가장 큰 소리가 이보다 가까우면 이만큼 벌려 본다 — 조용한 방의 잡음이 크게 보이지 않게.
  final double minSpan;

  /// 소리 하나마다 두 끝이 안쪽으로 돌아오는 양 (dB).
  final double drift;

  double? _floor, _ceil;

  double add(double db) {
    if (!db.isFinite) return 0;
    final floor = _floor = _floor == null ? db : math.min(db, _floor! + drift);
    final ceil = _ceil = _ceil == null ? db : math.max(db, _ceil! - drift);
    final span = math.max(ceil - floor, minSpan);
    return ((db - floor) / span).clamp(0.0, 1.0);
  }
}

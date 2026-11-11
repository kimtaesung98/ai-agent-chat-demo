/// 지난 대화 기억 — 끝난 대화 세션 요약을 페르소나마다 모아 둔다 (SPEC.md F-019, ARCHITECTURE.md ADR-024).
/// `package:flutter/foundation.dart`까지만 import한다 — 위젯 없이 단위 테스트한다.
/// 기기 저장은 [snapshot]·[MemoryController.restore]로 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

import '../api/models.dart';

export '../api/models.dart' show SessionSummary;

class MemoryController extends ChangeNotifier {
  MemoryController([List<SessionSummary> initial = const []]) : _all = [...initial]..sort(_byEnd);

  /// 저장해 둔 값으로 시작한다. 없거나 모양이 틀리면 빈 기억.
  factory MemoryController.restore(Object? saved) {
    if (saved is! Map) return MemoryController();
    final list = saved['sessions'];
    final seen = <String>{};
    return MemoryController([
      if (list is List)
        for (final item in list)
          if (SessionSummary.fromStoreJson(item) case final s? when seen.add(s.id)) s,
    ]).._trim();
  }

  /// 저장할 값 — [MemoryController.restore]가 읽는다.
  Map<String, Object> snapshot() => {
    'v': 1,
    'sessions': [for (final s in _all) s.toStoreJson()],
  };

  /// 페르소나마다 기기에 남기는 요약 수. 넘치면 오래된 것부터 지운다.
  static const keepPerPersona = 20;

  /// 다음 대화에 싣는 최근 요약 수 (API-001 `memory` 최대 5개).
  static const sendPerRequest = 5;

  final List<SessionSummary> _all; // 끝난 시각 순 (오래된 것부터)

  static int _byEnd(SessionSummary a, SessionSummary b) => a.endedAt.compareTo(b.endedAt);

  /// [personaId]의 요약, 최근 것부터 (화면용).
  List<SessionSummary> forPersona(String personaId) => [
    for (final s in _all.reversed)
      if (s.personaId == personaId) s,
  ];

  /// 다음 요청에 실을 최근 요약, 오래된 것부터 (F-019 AC4). 지금 대화 세션([exceptSession])은 내역이 따로 가니 뺀다.
  List<SessionSummary> recentFor(String personaId, {String? exceptSession}) {
    final list = [
      for (final s in _all)
        if (s.personaId == personaId && s.id != exceptSession) s,
    ];
    return list.length > sendPerRequest ? list.sublist(list.length - sendPerRequest) : list;
  }

  /// 요약을 넣는다. 같은 세션 id가 있으면 바꾼다 (대화를 이어 가다 다시 정리한 경우).
  void put(SessionSummary s) {
    _all
      ..removeWhere((e) => e.id == s.id)
      ..add(s)
      ..sort(_byEnd);
    _trim();
    notifyListeners();
  }

  /// 요약 하나를 지운다.
  void remove(String id) {
    final before = _all.length;
    _all.removeWhere((e) => e.id == id);
    if (_all.length != before) notifyListeners();
  }

  /// [personaId]의 기억을 모두 지운다.
  void clear(String personaId) {
    final before = _all.length;
    _all.removeWhere((e) => e.personaId == personaId);
    if (_all.length != before) notifyListeners();
  }

  void _trim() {
    final counts = <String, int>{};
    for (final s in _all) {
      counts[s.personaId] = (counts[s.personaId] ?? 0) + 1;
    }
    for (var i = 0; i < _all.length && counts.values.any((n) => n > keepPerPersona);) {
      final id = _all[i].personaId;
      if (counts[id]! > keepPerPersona) {
        counts[id] = counts[id]! - 1;
        _all.removeAt(i);
      } else {
        i++;
      }
    }
  }
}

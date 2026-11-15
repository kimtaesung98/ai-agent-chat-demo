/// 지난 대화 기억 — 끝난 대화 세션 요약을 페르소나마다 모아 둔다 (SPEC.md F-019, ARCHITECTURE.md ADR-024).
/// `package:flutter/foundation.dart`까지만 import한다 — 위젯 없이 단위 테스트한다.
/// 기기 저장은 [snapshot]·[MemoryController.restore]로 바깥(`storage/`)이 한다.
library;

import 'package:flutter/foundation.dart';

import '../api/account_api.dart';
import '../api/models.dart';

export '../api/models.dart' show LongTermMemory, SessionSummary, dayString;

class MemoryController extends ChangeNotifier {
  MemoryController([List<SessionSummary> initial = const [], List<LongTermMemory> longTerm = const []])
    : _all = [...initial]..sort(_byEnd),
      _longTerm = {for (final l in longTerm) l.personaId: l};

  /// 저장해 둔 값으로 시작한다. 없거나 모양이 틀리면 빈 기억.
  factory MemoryController.restore(Object? saved) {
    if (saved is! Map) return MemoryController();
    final list = saved['sessions'];
    final seen = <String>{};
    final longTerm = saved['longTerm'];
    return MemoryController(
      [
        if (list is List)
          for (final item in list)
            if (SessionSummary.fromStoreJson(item) case final s? when seen.add(s.id)) s,
      ],
      [
        if (longTerm is List)
          for (final item in longTerm) ?LongTermMemory.fromStoreJson(item),
      ],
    ).._trim();
  }

  /// 저장할 값 — [MemoryController.restore]가 읽는다.
  Map<String, Object> snapshot() => {
    'v': 1,
    'sessions': [for (final s in _all) s.toStoreJson()],
    'longTerm': [for (final l in _longTerm.values) l.toStoreJson()],
  };

  /// 로그인한 서버 계정 (F-028). 있으면 기억은 서버 값을 보여 주고, 지우기도 서버에 보낸다.
  AccountApi? _server;
  bool get serverBacked => _server != null;

  /// 기기 기억 — 서버에서 뗄 때 되돌린다.
  ({List<SessionSummary> all, Map<String, LongTermMemory> longTerm})? _device;

  /// 서버 계정에 붙인다. 기억은 [refresh]로 페르소나마다 받아 온다.
  void attachServer(AccountApi api) {
    if (_server == null) _device = (all: [..._all], longTerm: {..._longTerm});
    _server = api;
    _all.clear();
    _longTerm.clear();
    notifyListeners();
  }

  /// 서버에서 뗀다 (로그아웃). 기기 기억으로 되돌린다.
  void detachServer() {
    if (_server == null) return;
    _server = null;
    _all
      ..clear()
      ..addAll(_device?.all ?? const []);
    _longTerm
      ..clear()
      ..addAll(_device?.longTerm ?? const {});
    _device = null;
    notifyListeners();
  }

  /// [personaId]의 기억을 서버에서 다시 받는다 (F-028 AC4). 기기 모드면 아무것도 하지 않는다. 실패하면 있는 것을 그대로 둔다.
  Future<void> refresh(String personaId) async {
    final server = _server;
    if (server == null) return;
    try {
      final got = await server.memory(personaId);
      if (!identical(server, _server)) return;
      _all
        ..removeWhere((s) => s.personaId == personaId)
        ..addAll(got.summaries)
        ..sort(_byEnd);
      if (got.longTerm case final l?) {
        _longTerm[personaId] = l;
      } else {
        _longTerm.remove(personaId);
      }
      notifyListeners();
    } catch (_) {
      debugPrint('기억 불러오기 실패');
    }
  }

  /// 페르소나마다 기기에 남기는 요약 수. 넘치면 오래된 것부터 지운다.
  static const keepPerPersona = 20;

  /// 다음 대화에 싣는 최근 요약 수 (API-001 `memory` 최대 5개).
  static const sendPerRequest = 5;

  final List<SessionSummary> _all; // 끝난 시각 순 (오래된 것부터)
  final Map<String, LongTermMemory> _longTerm; // 페르소나 id → 장기 기억 (F-020)

  /// [personaId]의 장기 기억. 없으면 null.
  LongTermMemory? longTermFor(String personaId) => _longTerm[personaId];

  /// 장기 기억으로 아직 묶지 않은 오래된 요약, 오래된 것부터 (F-020 AC2).
  /// 최근 [sendPerRequest]개는 그대로 보내므로 빼고, 이미 묶은 시각([LongTermMemory.coversUntil]) 뒤의 것만.
  List<SessionSummary> pendingFold(String personaId) {
    final list = [
      for (final s in _all)
        if (s.personaId == personaId) s,
    ];
    if (list.length <= sendPerRequest) return const [];
    final covers = _longTerm[personaId]?.coversUntil;
    return [
      for (final s in list.sublist(0, list.length - sendPerRequest))
        if (covers == null || s.endedAt.isAfter(covers)) s,
    ];
  }

  /// 장기 기억을 넣는다 (같은 페르소나는 바꾼다).
  void setLongTerm(LongTermMemory l) {
    _longTerm[l.personaId] = l;
    notifyListeners();
  }

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
    _server?.deleteSummary(id).catchError((Object _) => debugPrint('요약 지우기 실패'));
  }

  /// [personaId]의 기억(요약·장기 기억)을 모두 지운다.
  void clear(String personaId) {
    final before = _all.length;
    _all.removeWhere((e) => e.personaId == personaId);
    final hadLongTerm = _longTerm.remove(personaId) != null;
    if (_all.length != before || hadLongTerm) notifyListeners();
    _server?.clearMemory(personaId).catchError((Object _) => debugPrint('기억 지우기 실패'));
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

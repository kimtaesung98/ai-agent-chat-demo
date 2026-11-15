/// 계정·개인 데이터 API 호출 (SPEC.md F-026~F-028, API-010~018). `chat`·`ui`를 import하지 않는다.
/// 세션은 서버가 주는 `HttpOnly` 쿠키 `sid`다 — 앱은 토큰을 보지도, 저장하지도 않는다 (같은 출처 fetch가 쿠키를 붙인다).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client_factory.dart';
import 'models.dart';

/// 서버 계정 API가 실패함. [message]는 화면에 보여도 되는 문장이다.
class AccountApiError implements Exception {
  const AccountApiError(this.status, this.code, this.message, {this.body});

  /// HTTP 상태. 연결 실패는 0.
  final int status;

  /// 서버 오류 코드 (`UNAUTHENTICATED`·`BAD_CODE`·`NOT_INVITED`·`CONFLICT`…). 연결 실패는 `NETWORK`.
  final String code;
  final String message;

  /// 오류 응답 본문 (409면 서버 값이 들어 있다).
  final Map<String, Object?>? body;

  bool get unauthenticated => status == 401 && code == 'UNAUTHENTICATED';
  bool get conflict => status == 409;
  bool get network => status == 0;

  @override
  String toString() => 'AccountApiError($status, $code)';
}

/// 로그인 화면에 보일 방법 (`GET /api/auth/options`).
class AuthOptions {
  const AuthOptions({this.code = true, this.google = false, this.googleClientId = '', this.guest = false});
  final bool code;
  final bool google;

  /// Google Identity Services에 넘길 클라이언트 ID (비밀값 아님). 비면 Google 버튼을 숨긴다.
  final String googleClientId;
  final bool guest;

  static AuthOptions fromJson(Map<String, Object?> j) => AuthOptions(
    code: j['code'] != false,
    google: j['google'] == true && j['googleClientId'] is String && (j['googleClientId'] as String).isNotEmpty,
    googleClientId: j['googleClientId'] is String ? j['googleClientId'] as String : '',
    guest: j['guest'] == true,
  );
}

/// 로그인한 사람 (`GET /api/me`의 `user`).
class ServerUser {
  const ServerUser({required this.id, required this.name, required this.role, this.google = false});
  final String id;
  final String name;

  /// `super_admin` · `caregiver` · `elder` · `guardian`.
  final String role;

  /// Google 계정이 연결되어 있는지.
  final bool google;

  static ServerUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], role = j['role'];
    if (id is! String || name is! String || role is! String) return null;
    return ServerUser(id: id, name: name, role: role, google: j['google'] == true);
  }
}

/// 내 프로필 (`GET·PUT /api/me/profile`).
class ServerProfile {
  const ServerProfile({
    this.about = '',
    this.textSize = '',
    this.voiceOnStart = false,
    this.lastPersonaId = '',
    this.saved = false,
  });
  final String about;

  /// 한 번이라도 저장한 프로필인지 (`updatedAt`이 있음). 아니면 설정은 기본값이라 기기 값을 덮지 않는다.
  final bool saved;

  /// `normal` · `large` · `xlarge`. 비면 정하지 않음.
  final String textSize;
  final bool voiceOnStart;
  final String lastPersonaId;

  static ServerProfile fromJson(Map<String, Object?> j) {
    final s = j['settings'];
    final settings = s is Map ? s : const {};
    return ServerProfile(
      about: j['about'] is String ? j['about'] as String : '',
      textSize: settings['textSize'] is String ? settings['textSize'] as String : '',
      voiceOnStart: settings['voiceOnStart'] == true,
      lastPersonaId: j['lastPersonaId'] is String ? j['lastPersonaId'] as String : '',
      saved: j['updatedAt'] is String,
    );
  }
}

/// 서버의 기억 (`GET /api/personas/{id}/memory`).
class ServerMemory {
  const ServerMemory({required this.summaries, this.longTerm});
  final List<SessionSummary> summaries;
  final LongTermMemory? longTerm;
}

/// 대화를 끝낸 결과 (`POST /api/conversations/{id}/end`). 메시지가 없으면 [summary]는 null.
class EndedConversation {
  const EndedConversation(this.summary);
  final SessionSummary? summary;
}

/// 계정 API 인터페이스. 컨트롤러는 이것만 알고, 테스트는 가짜를 쓴다.
abstract interface class AccountApi {
  Future<AuthOptions> options();

  /// 로그인 코드로 들어간다 (`POST /api/auth/code`). 틀리면 401 `BAD_CODE`, 너무 많이 틀리면 429.
  Future<ServerUser> loginWithCode(String code);

  /// Google ID 토큰으로 들어간다 (`POST /api/auth/google`). 연결 안 된 계정이면 403 `NOT_INVITED`.
  Future<ServerUser> loginWithGoogle(String idToken);

  /// 지금 세션의 사람. 세션이 없으면 null (401).
  Future<ServerUser?> me();

  Future<void> logout();

  Future<ServerProfile> profile();

  /// 보낸 필드만 바꾼다 (`PUT /api/me/profile`).
  Future<void> updateProfile({String? about, String? textSize, bool? voiceOnStart, String? lastPersonaId});

  /// 내 페르소나 (처음이면 서버가 탑재 4개를 넣는다).
  Future<List<Persona>> personas();
  Future<Persona> createPersona(Persona p);

  /// [Persona.revision]이 서버 값과 다르면 409 — [AccountApiError.body]의 `persona`가 서버 값이다.
  Future<Persona> updatePersona(Persona p);
  Future<void> deletePersona(String id);

  Future<ServerMemory> memory(String personaId);
  Future<void> clearMemory(String personaId);
  Future<void> deleteSummary(String summaryId);

  /// 대화를 연다. 대화 id(`cnv_…`)를 돌려준다.
  Future<String> openConversation(String personaId, {String channel = 'text'});

  /// 대화를 끝낸다. 서버가 원문으로 요약을 만들고 원문은 버린다 (F-028).
  Future<EndedConversation> endConversation(String id, List<Message> messages);

  /// 기기 데이터 한 번 옮기기 (`POST /api/import`, F-026 상세 동작 9). [payload]는 API-014 모양.
  Future<Map<String, Object?>> importDevice(Map<String, Object?> payload);
}

/// HTTP로 서버를 부르는 [AccountApi].
class HttpAccountApi implements AccountApi {
  HttpAccountApi({String baseUrl = '', http.Client Function()? clientFactory})
    : _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
      _newClient = clientFactory ?? createHttpClient;

  final String _base;
  final http.Client Function() _newClient;

  Uri _uri(String path) => _base.isEmpty ? Uri.base.resolve(path) : Uri.parse('$_base$path');

  static const _connect = '서버에 연결할 수 없어요. 네트워크를 확인해 주세요.';
  static const _failed = '요청을 처리하지 못했어요. 잠시 뒤 다시 해 주세요.';

  /// 요청을 보내고 JSON 객체(204면 빈 객체)를 받는다. 2xx가 아니면 [AccountApiError].
  Future<Map<String, Object?>> _send(String method, String path, [Object? body]) async {
    final client = _newClient();
    try {
      final req = http.Request(method, _uri(path));
      if (body != null) {
        req.headers['content-type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final http.Response res;
      try {
        res = await http.Response.fromStream(await client.send(req));
      } catch (_) {
        throw const AccountApiError(0, 'NETWORK', _connect);
      }
      Object? json;
      if (res.bodyBytes.isNotEmpty) {
        try {
          json = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          json = null;
        }
      }
      final map = json is Map<String, Object?> ? json : const <String, Object?>{};
      if (res.statusCode >= 200 && res.statusCode < 300) return map;
      final error = map['error'];
      final code = error is Map && error['code'] is String ? error['code'] as String : 'HTTP_${res.statusCode}';
      final message = error is Map && error['message'] is String ? error['message'] as String : _failed;
      throw AccountApiError(res.statusCode, code, message, body: map);
    } finally {
      client.close();
    }
  }

  ServerUser _user(Map<String, Object?> j) =>
      ServerUser.fromJson(j['user']) ?? (throw const AccountApiError(500, 'BAD_RESPONSE', _failed));

  @override
  Future<AuthOptions> options() async => AuthOptions.fromJson(await _send('GET', '/api/auth/options'));

  @override
  Future<ServerUser> loginWithCode(String code) async => _user(await _send('POST', '/api/auth/code', {'code': code}));

  @override
  Future<ServerUser> loginWithGoogle(String idToken) async =>
      _user(await _send('POST', '/api/auth/google', {'idToken': idToken}));

  @override
  Future<ServerUser?> me() async {
    try {
      return ServerUser.fromJson((await _send('GET', '/api/me'))['user']);
    } on AccountApiError catch (e) {
      if (e.status == 401) return null;
      rethrow;
    }
  }

  @override
  Future<void> logout() => _send('POST', '/api/auth/logout', const {});

  @override
  Future<ServerProfile> profile() async => ServerProfile.fromJson(await _send('GET', '/api/me/profile'));

  @override
  Future<void> updateProfile({String? about, String? textSize, bool? voiceOnStart, String? lastPersonaId}) => _send(
    'PUT',
    '/api/me/profile',
    {
      'about': ?about,
      if (textSize != null || voiceOnStart != null) 'settings': {'textSize': ?textSize, 'voiceOnStart': ?voiceOnStart},
      'lastPersonaId': ?lastPersonaId,
    },
  );

  @override
  Future<List<Persona>> personas() async {
    final list = (await _send('GET', '/api/personas'))['personas'];
    return [
      if (list is List)
        for (final p in list) ?Persona.fromV1Json(p),
    ];
  }

  Persona _persona(Map<String, Object?> j) =>
      Persona.fromV1Json(j) ?? (throw const AccountApiError(500, 'BAD_RESPONSE', _failed));

  @override
  Future<Persona> createPersona(Persona p) async => _persona(await _send('POST', '/api/personas', p.toV1Json()));

  @override
  Future<Persona> updatePersona(Persona p) async =>
      _persona(await _send('PUT', '/api/personas/${Uri.encodeComponent(p.id)}', p.toV1Json()));

  @override
  Future<void> deletePersona(String id) => _send('DELETE', '/api/personas/${Uri.encodeComponent(id)}');

  @override
  Future<ServerMemory> memory(String personaId) async {
    final j = await _send('GET', '/api/personas/${Uri.encodeComponent(personaId)}/memory');
    final list = j['summaries'];
    final lt = j['longTerm'];
    return ServerMemory(
      summaries: [
        if (list is List)
          for (final s in list) ?SessionSummary.fromServerJson(s, personaId: personaId),
      ],
      longTerm: lt is Map
          ? LongTermMemory.fromApiJson(
              lt,
              personaId: personaId,
              updatedAt: DateTime.tryParse('${lt['updatedAt']}') ?? DateTime.now(),
              coversUntil: DateTime.tryParse('${lt['coversUntil']}') ?? DateTime.now(),
            )
          : null,
    );
  }

  @override
  Future<void> clearMemory(String personaId) =>
      _send('DELETE', '/api/personas/${Uri.encodeComponent(personaId)}/memory');

  @override
  Future<void> deleteSummary(String summaryId) => _send('DELETE', '/api/summaries/${Uri.encodeComponent(summaryId)}');

  @override
  Future<String> openConversation(String personaId, {String channel = 'text'}) async {
    final id = (await _send('POST', '/api/conversations', {'personaId': personaId, 'channel': channel}))['id'];
    if (id is! String || id.isEmpty) throw const AccountApiError(500, 'BAD_RESPONSE', _failed);
    return id;
  }

  @override
  Future<EndedConversation> endConversation(String id, List<Message> messages) async {
    final j = await _send('POST', '/api/conversations/${Uri.encodeComponent(id)}/end', {
      'messages': [for (final m in messages) m.toJson()],
    });
    final s = j['summary'];
    final c = j['conversation'];
    final personaId = c is Map && c['personaId'] is String ? c['personaId'] as String : '';
    return EndedConversation(s is Map ? SessionSummary.fromServerJson(s, personaId: personaId) : null);
  }

  @override
  Future<Map<String, Object?>> importDevice(Map<String, Object?> payload) => _send('POST', '/api/import', payload);
}

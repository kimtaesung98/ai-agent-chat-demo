import 'dart:convert';
import 'dart:io';

import 'package:ai_agent_chat/api/account_api.dart';
import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/auth_controller.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/chat/display_settings.dart';
import 'package:ai_agent_chat/chat/memory_controller.dart';
import 'package:ai_agent_chat/chat/persona_controller.dart';
import 'package:ai_agent_chat/chat/server_sync.dart';
import 'package:ai_agent_chat/chat/start_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const elder = ServerUser(id: 'usr_elder', name: '순자', role: 'elder');

void main() {
  group('F-027 페르소나 형식 v1', () {
    test('F-027 AC4 서버 계약 예시 파일과 같은 JSON을 주고받고, 모르는 필드·base는 버린다', () {
      final example = jsonDecode(File('../server/contract/testdata/persona_v1.json').readAsStringSync()) as Map;
      final p = Persona.fromV1Json(example)!;
      expect(p.id, 'per_k3n9q2example');
      expect(p.presetId, 'elder-care');
      expect(p.revision, 3);
      expect(p.tones, ['다정하게', '천천히']);
      expect(p.instructions, '아침마다 혈압약 드셨는지 여쭤봐 줘');
      expect(isPresetPersona(p), isTrue);
      expect(p.toV1Json(), {
        'schema': 1,
        'kind': 'preset',
        'presetId': 'elder-care',
        'name': '노인복지사 미소',
        'role': '노인복지사',
        'tones': ['다정하게', '천천히'],
        'instructions': '아침마다 혈압약 드셨는지 여쭤봐 줘',
        'revision': 3,
      });
    });

    test('F-027 AC4 custom은 서버 instructions가 기본 지시이고, 보낼 때 기본 지시와 요구 사항을 합친다', () {
      final p = Persona.fromV1Json({
        'schema': 1,
        'id': 'per_x',
        'kind': 'custom',
        'name': '면접관',
        'instructions': '압박 면접처럼',
      })!;
      expect(p.base, '압박 면접처럼');
      expect(isPresetPersona(p), isFalse);
      expect(p.copyWith(instructions: '짧게').toV1Json()['instructions'], '압박 면접처럼\n짧게');
      expect(Persona.fromV1Json({'schema': 2, 'id': 'a', 'kind': 'custom', 'name': 'x'}), isNull);
      expect(
        Persona.fromV1Json({'schema': 1, 'id': 'a', 'kind': 'preset', 'name': 'x'}),
        isNull,
        reason: 'presetId 없음',
      );
    });

    test('F-027 AC5 서버 계정이면 저장은 PUT·POST, 실패하면 이전 값으로 돌리고 안내한다', () async {
      final api = FakeAccountApi(user: elder);
      final c = PersonaController()..attachServer(api, await api.personas());
      final before = c.selected;
      expect(await c.save(before.copyWith(instructions: '혈압약')), isNull);
      expect(api.calls, contains('updatePersona'));
      expect(c.selected.revision, before.revision + 1);

      api.fail['updatePersona'] = const AccountApiError(0, 'NETWORK', '서버에 연결할 수 없어요.');
      final saved = c.selected;
      expect(await c.save(saved.copyWith(name: '바꾼 이름')), '서버에 연결할 수 없어요.');
      expect(c.selected, saved, reason: '이전 값으로 돌아간다');

      final fresh = c.blank().copyWith(name: '면접관', base: '압박 면접처럼');
      expect(await c.save(fresh), isNull);
      expect(c.selected.id, startsWith('per_new'), reason: '서버 id로 바뀌고 선택된다');

      api.fail['createPersona'] = const AccountApiError(400, 'INVALID_INPUT', '페르소나는 20개까지예요.');
      final count = c.personas.length;
      expect(await c.save(c.blank().copyWith(name: '하나 더')), '페르소나는 20개까지예요.');
      expect(c.personas, hasLength(count), reason: '만들지 못한 것은 목록에서 뺀다');
    });

    test('F-027 AC5 다른 기기에서 먼저 고쳤으면(409) 서버 값으로 바꾸고 안내한다', () async {
      final api = FakeAccountApi(user: elder);
      final c = PersonaController()..attachServer(api, await api.personas());
      final mine = c.selected;
      api.serverPersonas[api.serverPersonas.indexWhere((p) => p.id == mine.id)] = mine.copyWith(
        name: '다른 기기 이름',
        revision: 5,
      );
      expect(await c.save(mine.copyWith(name: '내 이름')), PersonaMessages.conflict);
      expect(c.selected.name, '다른 기기 이름');
      expect(c.selected.revision, 5);
    });
  });

  group('F-028 대화·기억 서버 처리', () {
    late FakeApi chatApi;
    late FakeAccountApi api;
    late ChatController chat;
    late MemoryController memory;

    setUp(() async {
      chatApi = FakeApi();
      api = FakeAccountApi(user: elder);
      memory = MemoryController()..attachServer(api);
      final personas = PersonaController()..attachServer(api, await api.personas(), selectedId: 'per_friend');
      chat = ChatController(chatApi, personas: personas, memory: memory)..attachServer(api);
    });

    Future<void> exchange(String text) async {
      chat.send(text);
      await settle();
      chatApi.current
        ..add(const ChatDelta('네'))
        ..add(const ChatDone('end_turn'));
      await chatApi.current.close();
      await settle();
    }

    test('F-028 AC4 첫 메시지에 대화를 한 번 열고, 채팅은 conversationId만 보낸다 (페르소나·기억은 서버가)', () async {
      await exchange('안녕');
      await exchange('또 안녕');
      expect(api.opened, [(personaId: 'per_friend', channel: 'text')]);
      expect(chatApi.conversationIds, ['cnv_1', 'cnv_1']);
      expect(chatApi.requests.last, hasLength(3), reason: '내역은 지금처럼 앱이 보낸다');
    });

    test('F-028 AC4 새 대화면 /end 한 번 — 서버 요약이 기억에 보이고, 앱은 요약·장기 기억 API를 부르지 않는다', () async {
      await exchange('산책 다녀왔어요');
      chat.reset();
      chat.reset();
      await settle();
      expect(api.ended, hasLength(1));
      expect(api.ended.single.id, 'cnv_1');
      expect(api.ended.single.messages.first.content, '산책 다녀왔어요');
      expect(chatApi.summaryRequests, isEmpty);
      expect(chatApi.consolidateRequests, isEmpty);
      expect(memory.forPersona('per_friend').single.summary, '서버 요약: 산책 다녀왔어요');

      await exchange('다음 대화');
      expect(api.opened, hasLength(2), reason: '새 대화는 새로 연다');
    });

    test('F-028 AC4 /end가 실패하면 다음 정리 때 다시 보낸다', () async {
      await exchange('안녕');
      api.fail['endConversation'] = const AccountApiError(502, 'PROVIDER_ERROR', '잠시 뒤');
      expect(chat.endSession(), isTrue);
      await settle();
      expect(chat.endSession(), isTrue, reason: '실패했으니 다시');
      await settle();
      expect(api.ended, hasLength(1));
    });

    test('F-028 대화를 열지 못하면 답 자리에 안내 문장, 다시 시도하면 다시 연다', () async {
      api.fail['openConversation'] = const AccountApiError(429, 'QUOTA_EXCEEDED', '오늘은 여기까지예요.');
      chat.send('안녕');
      await settle();
      expect(chat.entries.last.status, EntryStatus.error);
      expect(chat.entries.last.text, '오늘은 여기까지예요.');
      expect(chat.retry(), isTrue);
      await settle();
      expect(api.opened, hasLength(1));
      expect(chatApi.conversationIds, ['cnv_1']);
    });

    test('F-028 실시간 음성은 voice 대화를 열어 그 id를 쓴다', () async {
      expect(await chat.voiceConversation(), 'cnv_1');
      expect(api.opened.single.channel, 'voice');
      expect(await chat.voiceConversation(), 'cnv_1', reason: '같은 대화');
      chat.detachServer();
      expect(await chat.voiceConversation(), isNull);
    });

    test('F-028 AC3 기억 화면은 서버 값을 받아 보여 주고, 지우기는 서버에 보낸다', () async {
      api.summaries.add(
        SessionSummary(id: 'sum_9', personaId: 'per_coach', endedAt: DateTime.utc(2026), summary: '영어'),
      );
      await memory.refresh('per_coach');
      expect(memory.forPersona('per_coach').single.id, 'sum_9');
      memory.remove('sum_9');
      await settle();
      expect(api.calls, contains('deleteSummary'));
      memory.clear('per_coach');
      await settle();
      expect(api.calls, contains('clearMemory'));
    });

    test('F-028 로그아웃 중에 끝난 요약은 기기 기억에 넣지 않는다', () async {
      await exchange('안녕');
      chat.endSession();
      chat.detachServer();
      memory.detachServer();
      await settle();
      expect(memory.forPersona('per_friend'), isEmpty);
    });
  });

  group('F-026 로그인 뒤 서버 데이터 맞추기', () {
    late FakeAccountApi api;
    late AuthController auth;
    late ChatController chat;
    late StartSettings start;
    late DisplaySettings display;
    late ServerSync sync;

    setUp(() {
      api = FakeAccountApi();
      auth = AuthController(api: api);
      chat = ChatController(FakeApi(), personas: PersonaController(), memory: MemoryController());
      start = StartSettings();
      display = DisplaySettings();
      sync = ServerSync(api: api, auth: auth, chat: chat, start: start, display: display);
    });

    test('F-026 로그인하면 서버 페르소나·프로필로 바꾸고, 로그아웃하면 뗀다', () async {
      api.profileValue = const ServerProfile(
        about: '무릎이 안 좋아요',
        textSize: 'xlarge',
        voiceOnStart: true,
        lastPersonaId: 'per_coach',
        saved: true,
      );
      await auth.signInWithCode('K7QM4XPH2R');
      await settle();
      expect(sync.state, SyncState.ready);
      expect(chat.personas!.serverBacked, isTrue);
      expect(chat.personas!.selected.id, 'per_coach');
      expect(chat.personas!.about, '무릎이 안 좋아요');
      expect(chat.serverBacked, isTrue);
      expect(chat.memory!.serverBacked, isTrue);
      expect(display.textSize, TextSize.xlarge);
      expect(start.voiceOnStart, isTrue);
      expect(auth.onboarded, isTrue, reason: '이미 대화 상대를 고른 계정');
      expect(api.profileUpdates, isEmpty, reason: '받은 값을 다시 보내지 않는다');

      await auth.signOut();
      await settle();
      expect(sync.state, SyncState.idle);
      expect(chat.personas!.serverBacked, isFalse);
      expect(chat.personas!.selected.id, isNot(startsWith('per_')));
      expect(chat.serverBacked, isFalse);
    });

    test('F-026 저장한 적 없는 프로필은 기기 설정을 덮지 않는다', () async {
      display.textSize = TextSize.large;
      await auth.signInWithCode('K7QM4XPH2R');
      await settle();
      expect(display.textSize, TextSize.large);
      expect(auth.onboarded, isFalse);
    });

    test('F-026 AC8 나에 대해·마지막 페르소나·글자 크기·켜면 바로 음성은 바뀔 때마다 서버에 보낸다', () async {
      await auth.signInWithCode('K7QM4XPH2R');
      await settle();
      chat.personas!.setAbout('70대예요');
      chat.personas!.select('per_coach');
      display.textSize = TextSize.xlarge;
      start.voiceOnStart = true;
      await settle();
      expect(api.profileUpdates, [
        {'about': '70대예요', 'lastPersonaId': 'per_elder-care'}, // 처음 고른 상대도 남긴다
        {'lastPersonaId': 'per_coach'},
        {'textSize': 'xlarge'},
        {'voiceOnStart': true},
      ]);
    });

    test('F-026 AC4 내 정보를 받을 때 세션이 끝났으면 로그인 화면으로', () async {
      api.fail['profile'] = const AccountApiError(401, 'UNAUTHENTICATED', '로그인이 필요해요.');
      await auth.signInWithCode('K7QM4XPH2R');
      await settle();
      expect(auth.signedIn, isFalse);
      expect(auth.error, isNotNull);
    });
  });
}

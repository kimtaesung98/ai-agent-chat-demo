import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:ai_agent_chat/voice/voice_controller.dart';
import 'package:ai_agent_chat/voice/voice_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  late FakeVoiceEngine engine;
  late VoiceController voice;
  late List<String> log; // 사건 순서 (speak · done 등)

  setUp(() {
    log = [];
    api = FakeApi();
    chat = ChatController(api);
    engine = FakeVoiceEngine(log);
    voice = VoiceController(chat, engine);
  });

  tearDown(() {
    voice.dispose();
    chat.dispose();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> say(String text) async {
    engine.hear(HeardPartial(text));
    engine.hear(HeardFinal(text));
    await pump();
  }

  Future<void> delta(String text) async {
    api.current.add(ChatDelta(text));
    await pump();
  }

  /// 읽기를 끝까지 마친다 (한 문장이 끝나야 다음 문장을 읽기 시작한다).
  Future<void> speakAll() async {
    await pump();
    while (engine.hasPending) {
      engine.finishAll();
      await pump();
    }
  }

  Future<void> done() async {
    log.add('done');
    api.current.add(const ChatDone('end_turn'));
    await pump();
  }

  test('F-012 AC1 말을 멈추면 버튼 없이 인식된 문장을 음성 모드로 보낸다', () async {
    await voice.start();
    expect(voice.state, VoiceState.listening);
    expect(engine.listening, isTrue);

    engine.hear(const HeardPartial('오늘 날씨'));
    await pump();
    expect(voice.partial, '오늘 날씨', reason: '인식 중인 문장 미리 보기');
    expect(api.requests, isEmpty);

    engine.hear(const HeardFinal('오늘 날씨 어때?'));
    await pump();
    expect(api.requests.single.last.content, '오늘 날씨 어때?');
    expect(api.modes.single, ChatMode.voice);
    expect(voice.state, VoiceState.thinking);
    expect(voice.partial, '');
  });

  test('F-012 AC2 첫 문장이 완성되면 done 전에 읽기 시작한다', () async {
    await voice.start();
    await say('안녕');
    await delta('안녕하세요. 반');
    expect(engine.spoken, ['안녕하세요.']);
    expect(voice.state, VoiceState.speaking);

    await delta('가워요! 오늘');
    await done();
    await speakAll();

    expect(log.indexOf('speak:안녕하세요.'), lessThan(log.indexOf('done')));
    expect(engine.spoken, ['안녕하세요.', '반가워요!', '오늘']);
  });

  test('F-012 AC4 다 읽으면 자동으로 다시 듣는다', () async {
    await voice.start();
    await say('안녕');
    await delta('네, 안녕하세요.');
    await done();
    expect(voice.state, VoiceState.speaking);

    await speakAll();
    expect(voice.state, VoiceState.listening);
    expect(engine.listening, isTrue);

    await say('두 번째 질문');
    expect(api.requests, hasLength(2));
    expect(api.requests.last.map((m) => m.content), ['안녕', '네, 안녕하세요.', '두 번째 질문']);
  });

  test('F-012 AC4 음성 모드를 끄면 듣기·읽기·요청이 모두 멈춘다', () async {
    await voice.start();
    await say('긴 설명 해 줘');
    await delta('첫 문장이에요. 두');
    expect(voice.state, VoiceState.speaking);

    voice.stop();
    await pump();
    expect(voice.state, VoiceState.off);
    expect(engine.listening, isFalse);
    expect(engine.cancels, greaterThan(0));
    expect(api.cancels, 1, reason: '진행 중인 요청 중단');
    expect(chat.entries.last.status, EntryStatus.stopped);

    await delta('번째');
    await speakAll();
    expect(voice.state, VoiceState.off);
    expect(engine.listening, isFalse, reason: '꺼진 뒤에는 다시 듣지 않는다');
  });

  test('F-012 AC5 읽는 중 사용자가 말하면 끼어들어 중단하고 새 질문을 보낸다', () async {
    await voice.start();
    await say('긴 설명 해 줘');
    await delta('첫 문장이에요. 두 번째 문장도 있');
    expect(voice.state, VoiceState.speaking);

    engine.hear(const HeardPartial('잠깐만'));
    await pump();
    expect(voice.state, VoiceState.listening);
    expect(engine.cancels, greaterThan(0), reason: '읽기를 바로 멈춘다');
    expect(api.cancels, 1, reason: '응답 생성도 중단 (F-003)');
    expect(chat.entries.last.status, EntryStatus.stopped);
    expect(chat.entries.last.text, '첫 문장이에요. 두 번째 문장도 있', reason: '받은 부분은 남는다');

    engine.hear(const HeardFinal('잠깐만 짧게 말해 줘'));
    await pump();
    expect(api.requests, hasLength(2));
    expect(api.requests.last.last.content, '잠깐만 짧게 말해 줘');
  });

  test('F-012 AC5 읽는 중 마이크 버튼을 누르면 끼어들어 듣기로 바뀐다', () async {
    await voice.start();
    await say('설명해 줘');
    await delta('첫 문장이에요. 두');
    voice.toggle();
    await pump();
    expect(voice.state, VoiceState.listening);
    expect(api.cancels, 1);
    expect(engine.listening, isTrue);
  });

  test('F-012 AC5 스피커 소리(에코)는 끼어들기로 보지 않는다', () async {
    await voice.start();
    await say('설명해 줘');
    await delta('오늘은 맑고 따뜻해요. 내');
    engine.hear(const HeardPartial('오늘은 맑고'));
    engine.hear(const HeardFinal('오늘은 막고 따뜻해요'));
    await pump();
    expect(voice.state, VoiceState.speaking);
    expect(api.cancels, 0);
    expect(api.requests, hasLength(1));
  });

  group('F-012 AC9 자기 답을 다시 듣지 않는다 (R-A09)', () {
    late DateTime now;

    setUp(() {
      voice.dispose();
      now = DateTime(2026, 11, 13, 18);
      voice = VoiceController(chat, engine, clock: () => now);
    });

    Future<void> answer(String text) async {
      await say('날씨 알려 줘');
      await delta(text);
      await done();
    }

    test('읽는 중 들린 답 조각이 다 읽은 뒤 확정돼도 질문으로 보내지 않는다', () async {
      await voice.start();
      await answer('오늘은 맑고 따뜻해요.');
      engine.hear(const HeardPartial('오늘은 막고'));
      await pump();
      expect(voice.state, VoiceState.speaking, reason: '에코는 끼어들기가 아니다');
      await speakAll();
      expect(voice.state, VoiceState.listening);
      now = now.add(const Duration(seconds: 2));
      engine.hear(const HeardFinal('오늘은 막고 따뜻해요'));
      await pump();
      expect(api.requests, hasLength(1), reason: '자기 답을 다시 보내지 않는다');
      expect(voice.partial, '');
      expect(engine.listening, isTrue);
    });

    test('다 읽은 직후 들린 답은 거르고, 이어서 한 사용자 말만 보낸다', () async {
      await voice.start();
      await answer('오늘은 맑고 따뜻해요.');
      await speakAll();
      now = now.add(const Duration(milliseconds: 500));
      engine.hear(const HeardPartial('따뜻해요'));
      await pump();
      expect(voice.partial, '', reason: '답 꼬리는 미리 보기에도 보이지 않는다');
      engine.hear(const HeardFinal('따뜻해요 그럼 내일은 어때'));
      await pump();
      expect(api.requests, hasLength(2));
      expect(api.requests.last.last.content, '그럼 내일은 어때');
    });

    test('읽는 중 말로 끼어들면 섞여 들린 답을 빼고 사용자 말만 보낸다', () async {
      await voice.start();
      await say('설명해 줘');
      await delta('오늘은 맑고 따뜻해요. 내');
      engine.hear(const HeardPartial('오늘은 맑고 따뜻해요 그런데 내일은 어때'));
      await pump();
      expect(voice.state, VoiceState.listening, reason: '사용자 말이 섞여 있으면 바로 끼어든다');
      expect(api.cancels, 1);
      expect(voice.partial, '그런데 내일은 어때');
      engine.hear(const HeardFinal('오늘은 맑고 따뜻해요 그런데 내일은 어때'));
      await pump();
      expect(api.requests.last.last.content, '그런데 내일은 어때');
    });

    test('한참 뒤에 답의 낱말을 따라 말하면 그대로 보낸다', () async {
      await voice.start();
      await answer('오늘은 맑고 따뜻해요.');
      await speakAll();
      now = now.add(const Duration(seconds: 5));
      await say('맑고 따뜻하네요');
      expect(api.requests.last.last.content, '맑고 따뜻하네요');
    });
  });

  test('F-012 서버 오류는 사용자용 문장을 읽어 주고 다시 듣는다', () async {
    await voice.start();
    await say('안녕');
    api.current.add(const ChatFailed('AI 서비스에 일시적인 문제가 있어요.'));
    await pump();
    expect(engine.spoken, ['AI 서비스에 일시적인 문제가 있어요.']);
    await speakAll();
    expect(voice.state, VoiceState.listening);
  });

  test('F-012 조용해서 듣기가 끝나면 다시 듣는다', () async {
    await voice.start();
    engine.listening = false;
    engine.hear(const ListenEnded());
    await pump();
    expect(engine.listening, isTrue);
    expect(voice.state, VoiceState.listening);
  });

  test('F-012 AC7 음성 인식 미지원이면 켜지지 않고 안내한다', () async {
    final v = VoiceController(chat, FakeVoiceEngine(log, false));
    addTearDown(v.dispose);
    await v.start();
    expect(v.state, VoiceState.off);
    expect(v.notice, VoiceMessages.unsupported);
  });

  test('F-012 AC7 마이크 권한을 거부하면 꺼지고 안내한다', () async {
    await voice.start();
    engine.hear(const ListenFailed(ListenFailure.notAllowed));
    await pump();
    expect(voice.state, VoiceState.off);
    expect(voice.notice, VoiceMessages.notAllowed);
    expect(chat.send('텍스트는 그대로'), isTrue, reason: '텍스트 채팅은 계속 동작');
  });

  test('F-017 AC4 모바일 앱에서는 브라우저가 아니라 기기 설정으로 안내한다', () {
    // 테스트는 웹이 아닌 VM에서 돈다 = 앱과 같은 문장
    expect(VoiceMessages.unsupported, VoiceMessages.unsupportedApp);
    expect(VoiceMessages.notAllowed, VoiceMessages.notAllowedApp);
    expect(VoiceMessages.notAllowedApp, isNot(contains('브라우저')));
    expect(VoiceMessages.unsupportedApp, isNot(contains('Chrome')));
  });

  test('F-012 텍스트로 보낸 질문은 음성 모드가 꺼져 있으면 읽지 않는다', () async {
    chat.send('텍스트 질문');
    await delta('답이에요. 끝');
    await done();
    expect(engine.spoken, isEmpty);
    expect(api.modes.single, ChatMode.text);
  });

  test('F-018 AC3 지금 읽는 문장을 자막으로 알려 주고, 끼어들거나 다 읽으면 비운다', () async {
    await voice.start();
    await say('안녕');
    expect(voice.sentence, isEmpty);
    await delta('첫 문장이에요. 두 번');
    expect(voice.sentence, '첫 문장이에요.');
    await delta('째예요. 끝');
    engine.finishAll();
    await pump();
    expect(voice.sentence, '두 번째예요.');

    voice.toggle(); // 끼어들기
    expect(voice.sentence, isEmpty);
    expect(voice.state, VoiceState.listening);

    await say('다시');
    await delta('짧아요.');
    await done();
    await speakAll();
    expect(voice.state, VoiceState.listening);
    expect(voice.sentence, isEmpty);
  });

  test('F-018 AC4 tap은 생각·읽는 중이면 끼어들고, 듣는 중이면 아무것도 하지 않는다', () async {
    voice.tap();
    await pump();
    expect(voice.state, VoiceState.listening);
    voice.tap();
    expect(voice.state, VoiceState.listening, reason: '잘못 눌러 꺼지지 않는다');

    await say('설명해 줘');
    await delta('첫 문장이에요. 두');
    expect(voice.state, VoiceState.speaking);
    voice.tap();
    expect(voice.state, VoiceState.listening);
    expect(chat.entries.last.status, EntryStatus.stopped);
  });

  test('F-018 AC6 끊기면 포기하지 않고 점점 늦게 다시 듣고, 권한 거부만 멈춘다', () async {
    voice.dispose();
    voice = VoiceController(chat, engine, retryDelay: const Duration(milliseconds: 10));
    await voice.start();
    for (final reason in [
      ListenFailure.other,
      ListenFailure.network,
      ListenFailure.noMicrophone,
      ListenFailure.other,
      ListenFailure.other,
    ]) {
      engine.hear(ListenFailed(reason));
      expect(voice.state, VoiceState.listening);
      expect(voice.notice, VoiceMessages.reconnecting);
      expect(engine.listening, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(engine.listening, isTrue, reason: '$reason 뒤에도 다시 듣는다');
    }
    engine.hear(const HeardPartial('들려요'));
    expect(voice.notice, isNull);

    engine.hear(const ListenFailed(ListenFailure.notAllowed));
    expect(voice.state, VoiceState.off);
    expect(voice.notice, VoiceMessages.notAllowed);
  });

  test('F-018 AC9 앱이 뒤로 가면 마이크를 놓고, 돌아오면 버튼 없이 다시 듣는다', () async {
    await voice.start();
    voice.pause();
    expect(engine.listening, isFalse);
    expect(voice.state, VoiceState.listening, reason: '음성 모드는 그대로');

    await say('뒤에서 들은 말');
    expect(api.requests, isEmpty, reason: '멈춘 동안 들은 것은 없다');

    voice.resume();
    expect(engine.listening, isTrue);
    await say('돌아왔어요');
    expect(api.requests.single.last.content, '돌아왔어요');
  });

  test('F-018 AC9 꺼진 상태에서는 돌아와도 듣지 않는다', () async {
    voice.pause();
    voice.resume();
    expect(engine.listening, isFalse);
    expect(voice.state, VoiceState.off);
  });
}

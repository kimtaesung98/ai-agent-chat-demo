import 'package:ai_agent_chat/api/chat_api.dart';
import 'package:ai_agent_chat/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late FakeApi api;
  late ChatController chat;
  setUp(() {
    api = FakeApi();
    chat = ChatController(api);
  });
  tearDown(() => chat.dispose());

  Future<void> flush() => pumpEventQueue();

  test('F-001 AC1 조각을 받는 대로 응답 말풍선에 이어 붙인다', () async {
    expect(chat.send('안녕'), isTrue);
    expect(chat.busy, isTrue);
    api.current.add(const ChatDelta('안'));
    await flush();
    expect(chat.entries.last.text, '안');
    api.current.add(const ChatDelta('녕'));
    await flush();
    expect(chat.entries.last.text, '안녕');
    expect(chat.entries.last.status, EntryStatus.streaming);
  });

  test('F-001 AC2 done을 받으면 바쁨 상태가 풀린다', () async {
    chat.send('안녕');
    api.current
      ..add(const ChatDelta('답'))
      ..add(const ChatDone('end_turn'));
    await flush();
    expect(chat.busy, isFalse);
    expect(chat.entries.last.status, EntryStatus.done);
  });

  test('F-001 AC3 빈 메시지와 응답 중 전송은 보내지 않는다', () async {
    expect(chat.send(''), isFalse);
    expect(chat.send('  \n '), isFalse);
    expect(api.requests, isEmpty);
    chat.send('첫');
    expect(chat.send('둘'), isFalse);
    expect(api.requests, hasLength(1));
  });

  test('F-001 AC4 서버 모드를 불러온다', () async {
    await chat.loadConfig();
    expect(chat.config!.isMock, isTrue);
  });

  test('F-002 AC1 이전 대화를 순서대로 함께 보낸다', () async {
    chat.send('첫 질문');
    api.current
      ..add(const ChatDelta('첫 답'))
      ..add(const ChatDone('end_turn'));
    await flush();
    chat.send('둘째 질문');
    expect(api.requests.last, const [
      Message(Role.user, '첫 질문'),
      Message(Role.assistant, '첫 답'),
      Message(Role.user, '둘째 질문'),
    ]);
  });

  test('F-002 AC3 새 대화는 화면과 내역을 비운다 (응답 중이면 먼저 멈춘다)', () async {
    chat.send('질문');
    chat.reset();
    expect(chat.entries, isEmpty);
    expect(chat.history, isEmpty);
    expect(chat.busy, isFalse);
    expect(api.cancels, 1);
  });

  test('F-003 AC1 중단하면 즉시 바쁨이 풀리고 이후 조각은 반영되지 않는다', () async {
    chat.send('길게 답해 줘');
    api.current.add(const ChatDelta('앞부분'));
    await flush();
    chat.stop();
    expect(chat.busy, isFalse);
    expect(api.cancels, 1);
    api.current.add(const ChatDelta('뒷부분')); // 취소 뒤 도착해도 무시
    await flush();
    expect(chat.entries.last.text, '앞부분');
  });

  test('F-003 AC3 중단된 응답은 남고 "중단됨" 상태이며 다음 요청 내역에 들어간다', () async {
    chat.send('질문');
    api.current.add(const ChatDelta('부분 답'));
    await flush();
    chat.stop();
    expect(chat.entries.last.status, EntryStatus.stopped);
    chat.send('다음');
    expect(api.requests.last, const [
      Message(Role.user, '질문'),
      Message(Role.assistant, '부분 답'),
      Message(Role.user, '다음'),
    ]);
  });

  test('F-003 아무것도 받기 전에 중단하면 빈 응답은 내역에서 빠진다', () async {
    chat.send('질문');
    chat.stop();
    chat.send('다음');
    expect(api.requests.last, const [Message(Role.user, '질문'), Message(Role.user, '다음')]);
  });

  test('F-004 AC1 실패하면 오류 말풍선을 보이고 실패한 질문은 내역에서 뺀다', () async {
    chat.send('질문');
    api.current.add(const ChatFailed('요청이 너무 많아요.'));
    await flush();
    expect(chat.busy, isFalse);
    expect(chat.entries.last.status, EntryStatus.error);
    expect(chat.entries.last.text, '요청이 너무 많아요.');
    expect(chat.history, isEmpty);
  });

  test('F-004 AC2 다시 시도하면 오류 말풍선을 지우고 마지막 사용자 메시지로 다시 요청한다', () async {
    chat.send('첫 질문');
    api.current
      ..add(const ChatDelta('첫 답'))
      ..add(const ChatDone('end_turn'));
    await flush();
    chat.send('두 번째');
    api.current.add(const ChatFailed('요청이 너무 많아요.'));
    await flush();
    expect(chat.canRetry, isTrue);

    expect(chat.retry(), isTrue);
    expect(api.requests.last, const [
      Message(Role.user, '첫 질문'),
      Message(Role.assistant, '첫 답'),
      Message(Role.user, '두 번째'),
    ]);
    expect(chat.entries.where((e) => e.status == EntryStatus.error), isEmpty);
    expect(chat.entries.length, 4);
    expect(chat.canRetry, isFalse); // 응답 중에는 다시 시도 없음

    api.current
      ..add(const ChatDelta('두 번째 답'))
      ..add(const ChatDone('end_turn'));
    await flush();
    expect(chat.history.length, 4);
  });

  test('F-004 AC2 마지막 답이 오류가 아니면 다시 시도하지 않는다', () async {
    expect(chat.retry(), isFalse);
    chat.send('질문');
    api.current.add(const ChatDone('end_turn'));
    await flush();
    final sent = api.requests.length;
    expect(chat.retry(), isFalse);
    expect(api.requests.length, sent);
  });

  test('F-001 done 없이 스트림이 끝나면 오류로 바꾼다', () async {
    chat.send('질문');
    api.current.add(const ChatDelta('앞'));
    await api.current.close();
    await flush();
    expect(chat.busy, isFalse);
    expect(chat.entries.last.status, EntryStatus.error);
  });
}

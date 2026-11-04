import { test } from 'node:test';
import assert from 'node:assert/strict';
import { trimToRecentTurns, MAX_TURNS } from '../src/server/context.js';
import { createChatController } from '../public/chat-controller.js';
import { startApp, postChat, readSSE } from './helpers.js';

/** n턴짜리 대화 (마지막은 응답 전 사용자 메시지) */
function conversation(turns) {
  const out = [];
  for (let i = 1; i <= turns; i++) {
    out.push({ role: 'user', content: `질문 ${i}` });
    if (i < turns) out.push({ role: 'assistant', content: `답변 ${i}` });
  }
  return out;
}

test('F-002 AC2 한도 이하면 그대로 둔다', () => {
  const msgs = conversation(MAX_TURNS);
  assert.deepEqual(trimToRecentTurns(msgs), msgs);
});

test('F-002 AC2 20턴을 넘으면 가장 오래된 턴부터 잘라 최근 20턴만 남긴다', () => {
  const trimmed = trimToRecentTurns(conversation(25));
  const users = trimmed.filter((m) => m.role === 'user');
  assert.equal(users.length, MAX_TURNS);
  assert.equal(trimmed[0].content, '질문 6', '1~5번 턴은 잘림');
  assert.equal(trimmed[0].role, 'user', '항상 사용자 메시지로 시작');
  assert.equal(trimmed.at(-1).content, '질문 25', '최신 메시지는 유지');
});

test('F-002 AC2 사용자 메시지가 연속돼도 턴 수를 올바르게 센다', () => {
  const msgs = [
    { role: 'user', content: 'a' },
    { role: 'user', content: 'b' },
    { role: 'assistant', content: 'x' },
    { role: 'user', content: 'c' },
  ];
  assert.deepEqual(trimToRecentTurns(msgs, 2).map((m) => m.content), ['b', 'x', 'c']);
});

test('F-002 AC2 앞쪽에 사용자 없이 시작하는 응답은 뗀다', () => {
  const msgs = [{ role: 'assistant', content: 'x' }, { role: 'user', content: 'a' }];
  assert.deepEqual(trimToRecentTurns(msgs), [{ role: 'user', content: 'a' }]);
});

test('F-002 AC2 서버는 제공자에 최근 20턴만 전달한다', async () => {
  let received;
  const recorder = {
    name: 'mock',
    model: 'x',
    async *stream(messages) {
      received = messages;
      yield { type: 'delta', text: 'ok' };
      yield { type: 'done', stopReason: 'end_turn' };
    },
  };
  const app = await startApp(recorder);
  try {
    await readSSE(await postChat(app.baseUrl, { messages: conversation(30) }));
    assert.equal(received.filter((m) => m.role === 'user').length, MAX_TURNS);
    assert.equal(received[0].content, '질문 11');
    assert.equal(received.at(-1).content, '질문 30');
  } finally {
    await app.close();
  }
});

// --- AC3 새 대화 ---

function fakeUi() {
  const calls = [];
  const ui = new Proxy({}, { get: (_t, name) => (...args) => calls.push([name, ...args]) });
  return { ui, calls };
}

const instantStream = async ({ onDelta, onDone }) => {
  onDelta('답');
  onDone({});
};

test('F-002 AC3 새 대화를 누르면 대화 영역과 내역이 비워진다', async () => {
  const { ui, calls } = fakeUi();
  const chat = createChatController({ ui, streamChat: instantStream });
  await chat.send('첫 질문');
  assert.equal(chat.history.length, 2);

  assert.equal(chat.reset(), true);
  assert.equal(chat.history.length, 0, '내역 비움');
  assert.deepEqual(calls.at(-1), ['clear'], '화면 비움');

  // 새 대화의 첫 요청에는 이전 내역이 없어야 함
  const sent = [];
  const chat2 = createChatController({ ui, streamChat: async (o) => (sent.push(o.messages), instantStream(o)) });
  await chat2.send('이전 질문');
  chat2.reset();
  await chat2.send('새 질문');
  assert.deepEqual(sent[1], [{ role: 'user', content: '새 질문' }]);
});

test('F-002 AC3 응답 중에는 새 대화를 무시한다 (중단은 F-003)', async () => {
  const { ui, calls } = fakeUi();
  let release;
  const chat = createChatController({
    ui,
    streamChat: ({ onDone }) => new Promise((r) => (release = () => (onDone({}), r()))),
  });
  const pending = chat.send('질문');
  assert.equal(chat.reset(), false);
  assert.ok(!calls.some(([n]) => n === 'clear'));
  release();
  await pending;
  assert.equal(chat.history.length, 2);
});

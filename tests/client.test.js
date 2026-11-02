import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { streamChat } from '../public/chat-client.js';
import { createChatController } from '../public/chat-controller.js';
import { createMockProvider } from '../src/agent/mock.js';
import { startApp } from './helpers.js';

let app;
before(async () => {
  app = await startApp(createMockProvider({ chunkDelayMs: 2 }));
});
after(() => app.close());

/** DOM 대신 호출 기록을 남기는 가짜 ui */
function fakeUi() {
  const calls = [];
  const ui = new Proxy({}, { get: (_t, name) => (...args) => calls.push([name, ...args]) });
  return { ui, calls };
}

const clientFor = (baseUrl) => (opts) => streamChat({ ...opts, url: `${baseUrl}/api/chat` });

test('F-001 AC1 화면에 delta가 도착 순서대로 이어 붙여진다', async () => {
  const { ui, calls } = fakeUi();
  const chat = createChatController({ ui, streamChat: clientFor(app.baseUrl) });
  await chat.send('순서 확인');
  const deltas = calls.filter(([n]) => n === 'appendDelta').map(([, t]) => t);
  assert.ok(deltas.length >= 2);
  const reply = chat.history[1].content;
  assert.equal(deltas.join(''), reply, '이어 붙인 결과 = 대화 내역에 저장된 응답');
  // 순서: appendUser → setBusy(true) → startAssistant → appendDelta… → finishAssistant → setBusy(false)
  const names = calls.map(([n]) => n);
  assert.deepEqual(names.slice(0, 3), ['appendUser', 'setBusy', 'startAssistant']);
  assert.deepEqual(names.slice(-2), ['finishAssistant', 'setBusy']);
});

test('F-001 AC2 응답이 끝나면 입력창이 다시 활성화된다', async () => {
  const { ui, calls } = fakeUi();
  const chat = createChatController({ ui, streamChat: clientFor(app.baseUrl) });
  const pending = chat.send('활성화 확인');
  assert.equal(chat.busy, true, '응답 중에는 바쁨 상태');
  assert.deepEqual(calls.find(([n]) => n === 'setBusy'), ['setBusy', true]);
  await pending;
  assert.equal(chat.busy, false);
  assert.deepEqual(calls.at(-1), ['setBusy', false]);
});

test('F-001 AC3 빈 메시지는 요청을 보내지 않는다', async () => {
  const { ui, calls } = fakeUi();
  let requests = 0;
  const chat = createChatController({ ui, streamChat: async () => requests++ });
  assert.equal(await chat.send(''), false);
  assert.equal(await chat.send('  \n '), false);
  assert.equal(requests, 0);
  assert.equal(calls.length, 0, '화면도 바뀌지 않음');
});

test('F-001 응답 중에 다시 보내면 무시한다', async () => {
  const { ui } = fakeUi();
  const chat = createChatController({ ui, streamChat: clientFor(app.baseUrl) });
  const first = chat.send('첫 번째');
  assert.equal(await chat.send('두 번째'), false);
  await first;
  assert.equal(chat.history.length, 2);
});

test('F-001 서버 400 오류 문구를 화면에 보여 주고 입력창을 다시 연다', async () => {
  const { ui, calls } = fakeUi();
  const chat = createChatController({ ui, streamChat: clientFor(app.baseUrl) });
  await chat.send('a'.repeat(4001));
  const error = calls.find(([n]) => n === 'showError');
  assert.ok(error);
  assert.match(error[1], /4,000자/);
  assert.equal(chat.history.length, 0, '실패한 질문은 내역에서 제외');
  assert.deepEqual(calls.at(-1), ['setBusy', false]);
});

test('F-002 AC1 (F-001 구현으로 충족) 이전 대화를 함께 보낸다', async () => {
  const sent = [];
  const { ui } = fakeUi();
  const chat = createChatController({
    ui,
    streamChat: async (opts) => {
      sent.push(opts.messages);
      return clientFor(app.baseUrl)(opts);
    },
  });
  await chat.send('첫 질문');
  await chat.send('두 번째 질문');
  assert.deepEqual(sent[1].map((m) => m.role), ['user', 'assistant', 'user']);
  assert.equal(sent[1][0].content, '첫 질문');
});

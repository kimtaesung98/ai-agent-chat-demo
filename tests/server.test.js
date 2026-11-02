import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createMockProvider } from '../src/agent/mock.js';
import { ProviderError } from '../src/agent/errors.js';
import { startApp, readSSE, postChat } from './helpers.js';

let app;
before(async () => {
  app = await startApp(createMockProvider({ chunkDelayMs: 5 }));
});
after(() => app.close());

test('F-001 AC1 done 전에 delta가 2개 이상 SSE로 도착하고 이어 붙이면 완전한 응답이 된다', async () => {
  const res = await postChat(app.baseUrl, { messages: [{ role: 'user', content: '스트리밍 테스트' }] });
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /^text\/event-stream/);

  const events = await readSSE(res);
  const deltas = events.filter((e) => e.event === 'delta');
  const done = events.find((e) => e.event === 'done');
  assert.ok(deltas.length >= 2, `delta ${deltas.length}개`);
  assert.ok(done, 'done 이벤트');
  assert.ok(deltas.every((d) => d.at < done.at), 'delta는 모두 done보다 먼저');
  assert.equal(done.at, events.length - 1, 'done이 마지막');
  assert.match(deltas.map((d) => d.data.text).join(''), /스트리밍 테스트/);
});

test('F-001 AC1 첫 delta는 전체 응답이 끝나기 전에 도착한다 (실제 스트리밍)', async () => {
  const slow = await startApp(createMockProvider({ chunkDelayMs: 20 }));
  try {
    const started = Date.now();
    const res = await postChat(slow.baseUrl, { messages: [{ role: 'user', content: '느린 응답' }] });
    const reader = res.body.getReader();
    await reader.read(); // 첫 조각
    const firstAt = Date.now() - started;
    while (!(await reader.read()).done);
    const totalAt = Date.now() - started;
    assert.ok(firstAt < totalAt / 2, `첫 조각 ${firstAt}ms, 전체 ${totalAt}ms`);
    assert.ok(firstAt < 1000, 'SPEC §1.3 첫 글자 1초 이내');
  } finally {
    await slow.close();
  }
});

test('F-001 AC3 빈 메시지·공백 메시지는 400', async () => {
  for (const content of ['', '   ']) {
    const res = await postChat(app.baseUrl, { messages: [{ role: 'user', content }] });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error.code, 'EMPTY_MESSAGE');
  }
});

test('F-001 AC5 4,000자 초과 메시지는 400', async () => {
  const res = await postChat(app.baseUrl, { messages: [{ role: 'user', content: 'a'.repeat(4001) }] });
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error.code, 'TOO_LONG');
});

test('F-001 잘못된 JSON은 400, 잘못된 메서드는 405, 없는 경로는 404', async () => {
  assert.equal((await postChat(app.baseUrl, '{oops')).status, 400);
  assert.equal((await fetch(`${app.baseUrl}/api/chat`)).status, 405);
  assert.equal((await fetch(`${app.baseUrl}/nope.js`)).status, 404);
});

test('F-001 AC4 /api/config는 현재 모드를 알려 준다', async () => {
  const res = await fetch(`${app.baseUrl}/api/config`);
  assert.deepEqual(await res.json(), { provider: 'mock', model: 'mock-echo' });
});

test('F-001 화면 파일을 제공하고 public/ 바깥과 README는 막는다', async () => {
  const index = await fetch(`${app.baseUrl}/`);
  assert.equal(index.status, 200);
  assert.match(await index.text(), /AI Agent Chat/);
  assert.match((await fetch(`${app.baseUrl}/app.js`)).headers.get('content-type'), /javascript/);
  assert.equal((await fetch(`${app.baseUrl}/README.md`)).status, 404);
  assert.equal((await fetch(`${app.baseUrl}/%2e%2e/package.json`)).status, 404);
});

test('F-001 제공자 오류는 error 이벤트로 전달되고 서버는 계속 동작한다', async () => {
  const failing = {
    name: 'mock',
    model: 'x',
    async *stream() {
      yield { type: 'delta', text: '일부' };
      throw new ProviderError('AI 서비스에 일시적인 문제가 있어요.');
    },
  };
  const broken = await startApp(failing);
  try {
    const events = await readSSE(await postChat(broken.baseUrl, { messages: [{ role: 'user', content: 'hi' }] }));
    assert.deepEqual(events.map((e) => e.event), ['delta', 'error']);
    assert.match(events[1].data.message, /일시적인 문제/);
    // 서버가 살아 있는지 다시 요청
    assert.equal((await fetch(`${broken.baseUrl}/api/config`)).status, 200);
  } finally {
    await broken.close();
  }
});

test('F-001 클라이언트가 연결을 끊으면 제공자에 취소 신호가 전달된다', async () => {
  let aborted = false;
  const endless = {
    name: 'mock',
    model: 'x',
    async *stream(_m, { signal }) {
      signal.addEventListener('abort', () => (aborted = true));
      while (!signal.aborted) {
        yield { type: 'delta', text: '.' };
        await new Promise((r) => setTimeout(r, 5));
      }
    },
  };
  const srv = await startApp(endless);
  try {
    const controller = new AbortController();
    const res = await fetch(`${srv.baseUrl}/api/chat`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ messages: [{ role: 'user', content: 'hi' }] }),
      signal: controller.signal,
    });
    const reader = res.body.getReader();
    await reader.read();
    controller.abort();
    for (let i = 0; i < 50 && !aborted; i++) await new Promise((r) => setTimeout(r, 10));
    assert.ok(aborted, '제공자 signal이 abort 되어야 함');
  } finally {
    await srv.close();
  }
});

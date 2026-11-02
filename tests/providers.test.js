import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createMockProvider } from '../src/agent/mock.js';
import { createAnthropicProvider } from '../src/agent/anthropic.js';
import { createProvider, DEFAULT_MODEL } from '../src/agent/index.js';
import { ProviderError } from '../src/agent/errors.js';
import { describeMode } from '../src/server/mode.js';

const FAKE_KEY = 'test-key-not-real';
const messages = [{ role: 'user', content: '안녕하세요' }];

async function collect(gen) {
  const out = [];
  for await (const c of gen) out.push(c);
  return out;
}

// --- 모의 제공자 ---

test('F-001 AC1 모의 제공자는 delta를 2개 이상 보낸 뒤 done으로 끝난다', async () => {
  const chunks = await collect(createMockProvider({ chunkDelayMs: 0 }).stream(messages));
  const deltas = chunks.filter((c) => c.type === 'delta');
  assert.ok(deltas.length >= 2);
  assert.deepEqual(chunks.at(-1), { type: 'done', stopReason: 'end_turn' });
  assert.match(deltas.map((d) => d.text).join(''), /안녕하세요/);
});

test('F-001 모의 제공자는 signal이 중단되면 멈춘다', async () => {
  const controller = new AbortController();
  const out = [];
  for await (const c of createMockProvider({ chunkDelayMs: 1 }).stream(messages, { signal: controller.signal })) {
    out.push(c);
    if (out.length === 2) controller.abort();
  }
  assert.equal(out.length, 2);
  assert.ok(!out.some((c) => c.type === 'done'));
});

// --- 제공자 선택 ---

test('F-001 AC4 API 키가 없으면 모의 모드, 있으면 Claude 모드', () => {
  assert.equal(createProvider({}).name, 'mock');
  assert.equal(createProvider({ ANTHROPIC_API_KEY: '   ' }).name, 'mock');
  const p = createProvider({ ANTHROPIC_API_KEY: FAKE_KEY });
  assert.equal(p.name, 'anthropic');
  assert.equal(p.model, DEFAULT_MODEL);
  assert.equal(createProvider({ ANTHROPIC_API_KEY: FAKE_KEY, ANTHROPIC_MODEL: 'claude-haiku-5-5' }).model, 'claude-haiku-5-5');
});

test('F-001 AC4 시작 로그 문구에 모드가 표시되고 키는 들어가지 않는다', () => {
  assert.match(describeMode(createProvider({})), /모의\(mock\)/);
  const line = describeMode(createProvider({ ANTHROPIC_API_KEY: FAKE_KEY }));
  assert.match(line, /Claude/);
  assert.ok(!line.includes(FAKE_KEY));
});

// --- Claude 제공자 (가짜 업스트림 서버, 실제 API 호출 없음) ---

/** 문서에 나온 스트리밍 응답 형식을 그대로 흉내 내는 가짜 Messages API */
async function fakeUpstream(handler) {
  const seen = {};
  const server = http.createServer(async (req, res) => {
    let body = '';
    for await (const c of req) body += c;
    seen.method = req.method;
    seen.url = req.url;
    seen.headers = req.headers;
    seen.body = JSON.parse(body);
    handler(req, res);
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return {
    seen,
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise((r) => server.close(r)),
  };
}

const sse = (event, data) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

test('F-001 AC1 Claude 스트림의 text_delta를 순서대로 delta로 바꾸고 요청 형식을 지킨다', async () => {
  const up = await fakeUpstream((req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(sse('message_start', { type: 'message_start', message: { id: 'msg_1', content: [] } }));
    res.write(sse('content_block_start', { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } }));
    res.write(sse('ping', { type: 'ping' }));
    res.write(sse('content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '안녕' } }));
    // 두 이벤트를 한 패킷 경계에 걸치게 쪼개 보낸다
    const split = sse('content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '하세요!' } });
    res.write(split.slice(0, 10));
    res.write(split.slice(10));
    res.write(sse('some_future_event', { type: 'some_future_event' }));
    res.write(sse('content_block_stop', { type: 'content_block_stop', index: 0 }));
    res.write(sse('message_delta', { type: 'message_delta', delta: { stop_reason: 'end_turn' }, usage: { output_tokens: 3 } }));
    res.end(sse('message_stop', { type: 'message_stop' }));
  });
  try {
    const provider = createAnthropicProvider({ apiKey: FAKE_KEY, model: 'claude-sonnet-5-5', baseUrl: up.baseUrl });
    const chunks = await collect(provider.stream(messages));
    assert.deepEqual(chunks, [
      { type: 'delta', text: '안녕' },
      { type: 'delta', text: '하세요!' },
      { type: 'done', stopReason: 'end_turn' },
    ]);
    assert.equal(up.seen.url, '/v1/messages');
    assert.equal(up.seen.headers['x-api-key'], FAKE_KEY);
    assert.equal(up.seen.headers['anthropic-version'], '2023-06-01');
    assert.equal(up.seen.body.stream, true);
    assert.equal(up.seen.body.model, 'claude-sonnet-5-5');
    assert.deepEqual(up.seen.body.messages, messages);
  } finally {
    await up.close();
  }
});

test('F-001 스트림 중 error 이벤트는 키가 없는 사용자용 ProviderError가 된다', async () => {
  const up = await fakeUpstream((req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(sse('content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '부분' } }));
    res.end(sse('error', { type: 'error', error: { type: 'overloaded_error', message: 'Overloaded' } }));
  });
  try {
    const provider = createAnthropicProvider({ apiKey: FAKE_KEY, model: 'm', baseUrl: up.baseUrl });
    const out = [];
    await assert.rejects(
      (async () => {
        for await (const c of provider.stream(messages)) out.push(c);
      })(),
      (err) => err instanceof ProviderError && /일시적인 문제/.test(err.userMessage) && !err.userMessage.includes(FAKE_KEY),
    );
    assert.deepEqual(out, [{ type: 'delta', text: '부분' }]);
  } finally {
    await up.close();
  }
});

test('F-001 HTTP 오류 응답은 상태별 사용자 문구로 바뀌고 업스트림 원문을 노출하지 않는다', async () => {
  const up = await fakeUpstream((req, res) => {
    res.writeHead(401, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ type: 'error', error: { type: 'authentication_error', message: `invalid x-api-key ${FAKE_KEY}` } }));
  });
  try {
    const provider = createAnthropicProvider({ apiKey: FAKE_KEY, model: 'm', baseUrl: up.baseUrl });
    await assert.rejects(collect(provider.stream(messages)), (err) => {
      assert.ok(err instanceof ProviderError);
      assert.equal(err.status, 401);
      assert.match(err.userMessage, /인증/);
      assert.ok(!err.userMessage.includes(FAKE_KEY));
      assert.ok(!err.message.includes(FAKE_KEY));
      return true;
    });
  } finally {
    await up.close();
  }
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateChatRequest, MAX_CONTENT_LENGTH } from '../src/server/validate.js';

const user = (content) => ({ role: 'user', content });

test('F-001 AC3 빈 메시지는 거절한다', () => {
  assert.equal(validateChatRequest({ messages: [user('')] }).ok, false);
  assert.equal(validateChatRequest({ messages: [] }).ok, false);
});

test('F-001 AC3 공백만 있는 메시지는 거절한다', () => {
  const r = validateChatRequest({ messages: [user('   \n\t ')] });
  assert.equal(r.ok, false);
  assert.equal(r.code, 'EMPTY_MESSAGE');
});

test('F-001 AC5 4,000자를 넘으면 거절하고 4,000자는 허용한다', () => {
  assert.equal(validateChatRequest({ messages: [user('가'.repeat(MAX_CONTENT_LENGTH + 1))] }).code, 'TOO_LONG');
  assert.equal(validateChatRequest({ messages: [user('가'.repeat(MAX_CONTENT_LENGTH))] }).ok, true);
});

test('F-001 형식이 틀린 요청은 거절한다', () => {
  for (const body of [null, {}, { messages: 'hi' }, { messages: [{ role: 'system', content: 'x' }] }, { messages: [{ role: 'user', content: 1 }] }]) {
    assert.equal(validateChatRequest(body).ok, false, JSON.stringify(body));
  }
});

test('F-001 마지막 메시지가 assistant면 거절한다', () => {
  const r = validateChatRequest({ messages: [user('안녕'), { role: 'assistant', content: '네' }] });
  assert.equal(r.ok, false);
});

test('F-001 정상 요청은 필요한 필드만 남긴다', () => {
  const r = validateChatRequest({ messages: [{ role: 'user', content: '안녕', extra: true }] });
  assert.deepEqual(r, { ok: true, messages: [{ role: 'user', content: '안녕' }] });
});

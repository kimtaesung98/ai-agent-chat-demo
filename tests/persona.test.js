import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateChatRequest } from '../src/server/validate.js';
import { parsePersona, personaSystemPrompt } from '../src/server/persona.js';
import { VOICE_SYSTEM_PROMPT } from '../src/server/voice.js';
import { startApp, readSSE } from './helpers.js';

const user = (content) => ({ role: 'user', content });
const long = (n) => '가'.repeat(n);

test('F-005 AC4 페르소나 프롬프트는 이름·역할·말투·지시·사용자 정보를 담고 Go와 같은 문장이다', () => {
  const p = parsePersona({ name: ' 지은 ', role: '기획 파트너', tones: ['차분하게', ' 존댓말 '], instructions: '질문으로 정리', about: '32살 기획자' });
  assert.equal(
    personaSystemPrompt(p),
    '당신은 사용자와 대화하는 에이전트 "지은"예요. 아래 설정에 맞는 인물로서 답하세요.\n' +
      '역할: 기획 파트너\n말투: 차분하게, 존댓말\n사용자가 정한 추가 지시: 질문으로 정리\n' +
      '사용자에 대해 (사용자가 직접 알려 준 정보예요. 대화 맥락으로 참고하되, 묻지 않으면 그대로 되풀이하지 마세요): 32살 기획자',
  );
  assert.equal(personaSystemPrompt(parsePersona({ name: '친구' })).includes('\n'), false, '빈 필드는 줄을 만들지 않는다');
});

test('F-005 AC5 올바른 persona는 받아들이고 생략하면 null', () => {
  assert.equal(validateChatRequest({ messages: [user('q')] }).persona, null);
  for (const persona of [
    { name: '친구' },
    { name: '친구', tones: [], role: '', unknown: 1 },
    { name: long(40), role: long(40), tones: [long(20), 'a', 'b', 'c', 'd', 'e'], instructions: long(1000), about: long(1000) },
  ]) {
    assert.equal(validateChatRequest({ messages: [user('q')], persona }).ok, true, JSON.stringify(persona).slice(0, 80));
  }
});

test('F-005 AC5 persona 형식이 틀리면 INVALID_INPUT', () => {
  for (const persona of [
    null, '지은', 1, [], true, {}, { name: '' }, { name: '   ' }, { name: 1 }, { name: null }, { name: long(41) },
    { name: 'a', role: long(41) }, { name: 'a', role: 3 }, { name: 'a', tones: '차분하게' }, { name: 'a', tones: ['a', 1] },
    { name: 'a', tones: [''] }, { name: 'a', tones: [long(21)] }, { name: 'a', tones: ['1', '2', '3', '4', '5', '6', '7'] },
    { name: 'a', instructions: long(1001) }, { name: 'a', about: long(1001) }, { name: 'a', about: false }, { name: 'a', tones: null },
  ]) {
    const r = validateChatRequest({ messages: [user('q')], persona });
    assert.equal(r.ok, false, JSON.stringify(persona));
    assert.equal(r.code, 'INVALID_INPUT');
  }
});

test('F-005 AC4 서버는 페르소나 프롬프트를, voice면 그 뒤에 말하기 지시를 제공자에 넘긴다', async () => {
  const seen = [];
  const app = await startApp({
    name: 'mock',
    model: 'fake',
    async *stream(_m, { system }) {
      seen.push(system);
      yield { type: 'done', stopReason: 'end_turn' };
    },
  });
  try {
    const persona = { name: '지은', role: '기획 파트너' };
    const expected = personaSystemPrompt(parsePersona(persona));
    for (const body of [{ messages: [user('q')], persona }, { messages: [user('q')], persona, mode: 'voice' }]) {
      const res = await fetch(`${app.baseUrl}/api/chat`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
      await readSSE(res);
    }
    assert.deepEqual(seen, [expected, `${expected}\n\n${VOICE_SYSTEM_PROMPT}`]);
  } finally {
    await app.close();
  }
});

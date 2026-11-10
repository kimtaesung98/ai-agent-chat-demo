/**
 * POST /api/chat 입력 검증 — 규칙은 이 파일 한 곳에서만 정의한다 (src/server/README.md).
 * SPEC.md §7.2 ChatMessage: role ∈ {user, assistant}, content 1~4,000자, 공백만은 불가.
 */

import { MODES } from './voice.js';
import { parsePersona, PERSONA_INVALID_MESSAGE } from './persona.js';

export const MAX_CONTENT_LENGTH = 4000;
const ROLES = new Set(['user', 'assistant']);

/**
 * @param {unknown} body
 * @returns {{ ok: true, messages: { role: 'user' | 'assistant', content: string }[], mode: 'text' | 'voice', persona: ReturnType<typeof parsePersona> }
 *         | { ok: false, code: string, message: string }}
 */
export function validateChatRequest(body) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.messages)) {
    return fail('INVALID_INPUT', '요청 형식이 올바르지 않아요. messages 배열이 필요해요.');
  }
  const { messages } = body;
  // mode (선택, F-012): 생략하면 text. Go와 같이 messages 배열 확인 다음, 빈 목록 확인 전에 검사한다
  const mode = body.mode === undefined ? 'text' : body.mode;
  if (!MODES.has(mode)) {
    return fail('INVALID_INPUT', '요청 형식이 올바르지 않아요. mode는 text 또는 voice여야 해요.');
  }
  // persona (선택, F-005): Go와 같이 mode 다음에 검사한다
  let persona = null;
  if ('persona' in body) {
    persona = parsePersona(body.persona);
    if (!persona) return fail('INVALID_INPUT', PERSONA_INVALID_MESSAGE);
  }
  if (messages.length === 0) {
    return fail('EMPTY_MESSAGE', '메시지를 입력해 주세요.');
  }

  const clean = [];
  for (const m of messages) {
    if (!m || typeof m !== 'object' || !ROLES.has(m.role) || typeof m.content !== 'string') {
      return fail('INVALID_INPUT', '메시지 형식이 올바르지 않아요.');
    }
    if (m.content.trim() === '') {
      return fail('EMPTY_MESSAGE', '메시지를 입력해 주세요.');
    }
    if (m.content.length > MAX_CONTENT_LENGTH) {
      return fail('TOO_LONG', `메시지는 ${MAX_CONTENT_LENGTH.toLocaleString('ko-KR')}자까지 보낼 수 있어요.`);
    }
    clean.push({ role: m.role, content: m.content });
  }

  if (clean.at(-1).role !== 'user') {
    return fail('INVALID_INPUT', '마지막 메시지는 사용자 메시지여야 해요.');
  }
  return { ok: true, messages: clean, mode, persona };
}

function fail(code, message) {
  return { ok: false, code, message };
}

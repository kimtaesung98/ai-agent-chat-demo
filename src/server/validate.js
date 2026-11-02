/**
 * POST /api/chat 입력 검증 — 규칙은 이 파일 한 곳에서만 정의한다 (src/server/README.md).
 * SPEC.md §7.2 ChatMessage: role ∈ {user, assistant}, content 1~4,000자, 공백만은 불가.
 */

export const MAX_CONTENT_LENGTH = 4000;
const ROLES = new Set(['user', 'assistant']);

/**
 * @param {unknown} body
 * @returns {{ ok: true, messages: { role: 'user' | 'assistant', content: string }[] }
 *         | { ok: false, code: string, message: string }}
 */
export function validateChatRequest(body) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.messages)) {
    return fail('INVALID_INPUT', '요청 형식이 올바르지 않아요. messages 배열이 필요해요.');
  }
  const { messages } = body;
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
  return { ok: true, messages: clean };
}

function fail(code, message) {
  return { ok: false, code, message };
}

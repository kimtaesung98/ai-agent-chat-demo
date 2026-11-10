/**
 * 페르소나 (SPEC.md F-005, API-001 persona, ARCHITECTURE.md ADR-016).
 * Go server/internal/chat/persona.go와 같은 규칙·문장이다 — 한쪽을 바꾸면 다른 쪽도 바꾼다.
 */

export const PERSONA_LIMITS = { name: 40, role: 40, tones: 6, tone: 20, instructions: 1000, about: 1000 };

export const PERSONA_INVALID_MESSAGE = '요청 형식이 올바르지 않아요. persona 형식을 확인해 주세요.';

const ABOUT_LABEL =
  '사용자에 대해 (사용자가 직접 알려 준 정보예요. 대화 맥락으로 참고하되, 묻지 않으면 그대로 되풀이하지 마세요): ';

/**
 * persona 값을 검증한다. 모르는 필드는 무시한다.
 * @param {unknown} raw
 * @returns {{ name: string, role: string, tones: string[], instructions: string, about: string } | null} 형식이 틀리면 null
 */
export function parsePersona(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const str = (key, max, required) => {
    if (!(key in raw)) return required ? null : '';
    const v = raw[key];
    if (typeof v !== 'string') return null;
    const s = v.trim();
    if (s.length > max || (required && s === '')) return null;
    return s;
  };
  const name = str('name', PERSONA_LIMITS.name, true);
  const role = str('role', PERSONA_LIMITS.role, false);
  const instructions = str('instructions', PERSONA_LIMITS.instructions, false);
  const about = str('about', PERSONA_LIMITS.about, false);
  if (name === null || role === null || instructions === null || about === null) return null;

  const tones = [];
  if ('tones' in raw) {
    if (!Array.isArray(raw.tones) || raw.tones.length > PERSONA_LIMITS.tones) return null;
    for (const t of raw.tones) {
      if (typeof t !== 'string') return null;
      const s = t.trim();
      if (s === '' || s.length > PERSONA_LIMITS.tone) return null;
      tones.push(s);
    }
  }
  return { name, role, tones, instructions, about };
}

/** 페르소나를 시스템 프롬프트로 바꾼다. 빈 필드는 줄을 만들지 않는다. */
export function personaSystemPrompt(p) {
  if (!p) return '';
  const lines = [`당신은 사용자와 대화하는 에이전트 "${p.name}"예요. 아래 설정에 맞는 인물로서 답하세요.`];
  if (p.role) lines.push(`역할: ${p.role}`);
  if (p.tones.length > 0) lines.push(`말투: ${p.tones.join(', ')}`);
  if (p.instructions) lines.push(`사용자가 정한 추가 지시: ${p.instructions}`);
  if (p.about) lines.push(ABOUT_LABEL + p.about);
  return lines.join('\n');
}

/**
 * 음성 대화 말투 (SPEC.md F-012, ARCHITECTURE.md ADR-015).
 * Go server/internal/chat VoiceSystemPrompt와 같은 문장이다 — 한쪽을 바꾸면 다른 쪽도 바꾼다.
 */

export const MODES = new Set(['text', 'voice']);

export const VOICE_SYSTEM_PROMPT =
  '지금은 음성 대화예요. 답은 소리 내어 읽혀요. ' +
  '사람과 마주 보고 이야기하듯 자연스러운 구어체로, 보통 한두 문장, 길어도 세 문장 안으로 짧게 답하세요. ' +
  '마크다운, 목록, 표, 코드, 이모지, URL은 쓰지 마세요. 숫자와 단위는 소리 내어 읽기 쉽게 쓰세요. ' +
  '설명이 길어질 것 같으면 핵심부터 말하고 더 들을지 물어보세요. 사용자가 다른 언어로 말하면 그 언어로 답하세요.';

/** 말투에 맞는 시스템 프롬프트. 텍스트는 빈 문자열. */
export function systemPromptFor(mode) {
  return mode === 'voice' ? VOICE_SYSTEM_PROMPT : '';
}

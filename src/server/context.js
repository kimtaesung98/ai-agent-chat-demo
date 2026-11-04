/**
 * 대화 맥락 정리 (SPEC.md F-002 AC2).
 * 턴 = 사용자 메시지 1개 + 그 뒤의 에이전트 응답. 최근 maxTurns개 턴만 남기고 오래된 턴부터 자른다.
 * 잘린 결과는 항상 사용자 메시지로 시작한다.
 */

export const MAX_TURNS = 20;

/**
 * @template {{ role: string, content: string }} M
 * @param {M[]} messages 검증을 통과한 대화 내역 (마지막은 user)
 * @param {number} [maxTurns]
 * @returns {M[]}
 */
export function trimToRecentTurns(messages, maxTurns = MAX_TURNS) {
  let turns = 0;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'user') {
      turns++;
      if (turns === maxTurns) return messages.slice(i);
    }
  }
  // 턴 수가 한도 이하면 그대로 두되, 앞쪽에 user 없이 시작하는 assistant 메시지는 뗀다
  const firstUser = messages.findIndex((m) => m.role === 'user');
  return firstUser > 0 ? messages.slice(firstUser) : messages;
}

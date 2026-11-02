/**
 * 모의 제공자 — API 키 없이 시연·테스트하기 위한 제공자 (SPEC.md ADR-003).
 * 마지막 사용자 메시지를 바탕으로 정해진 답을 만들고, 몇 글자씩 나눠 흘려보낸다.
 */

const CHUNK_SIZE = 4;

/**
 * @param {{ chunkDelayMs?: number }} [options]
 */
export function createMockProvider({ chunkDelayMs = 30 } = {}) {
  return {
    name: 'mock',
    model: 'mock-echo',
    async *stream(messages, { signal } = {}) {
      const reply = buildReply(messages);
      for (let i = 0; i < reply.length; i += CHUNK_SIZE) {
        if (signal?.aborted) return;
        await sleep(chunkDelayMs, signal);
        if (signal?.aborted) return;
        yield { type: 'delta', text: reply.slice(i, i + CHUNK_SIZE) };
      }
      yield { type: 'done', stopReason: 'end_turn' };
    },
  };
}

function buildReply(messages) {
  const last = [...messages].reverse().find((m) => m.role === 'user');
  const quoted = truncate(last?.content.trim() ?? '', 60);
  const turn = messages.filter((m) => m.role === 'user').length;
  return [
    `모의 모드 응답이에요. 받은 메시지: "${quoted}"`,
    `지금은 이 대화의 ${turn}번째 질문이에요.`,
    'ANTHROPIC_API_KEY를 설정하고 서버를 다시 시작하면 실제 Claude가 답해요.',
  ].join('\n');
}

function truncate(text, max) {
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

function sleep(ms, signal) {
  return new Promise((resolve) => {
    if (ms <= 0) return resolve();
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        resolve();
      },
      { once: true },
    );
  });
}

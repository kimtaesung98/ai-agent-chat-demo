/**
 * POST /api/chat 호출과 SSE 파싱. DOM에 접근하지 않는다 (public/README.md Agent Control).
 * EventSource는 GET만 지원해서 fetch + ReadableStream으로 읽는다 (SPEC.md ADR-002).
 *
 * @param {{
 *   messages: { role: string, content: string }[],
 *   onDelta: (text: string) => void,
 *   onDone?: (info: { stopReason?: string }) => void,
 *   onError?: (message: string) => void,
 *   signal?: AbortSignal,
 *   url?: string,
 *   fetchImpl?: typeof fetch,
 * }} options
 */
export async function streamChat({
  messages,
  onDelta,
  onDone = () => {},
  onError = () => {},
  signal,
  url = '/api/chat',
  fetchImpl = (...args) => fetch(...args),
}) {
  let res;
  try {
    res = await fetchImpl(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ messages }),
      signal,
    });
  } catch {
    if (!signal?.aborted) onError('서버에 연결할 수 없어요. 네트워크를 확인해 주세요.');
    return;
  }

  if (!res.ok) {
    let message = '요청을 처리하지 못했어요.';
    try {
      message = (await res.json())?.error?.message ?? message;
    } catch {
      /* 본문이 JSON이 아니면 기본 문구 사용 */
    }
    onError(message);
    return;
  }

  let finished = false;
  try {
    for await (const { event, data } of readEvents(res.body)) {
      const payload = JSON.parse(data);
      if (event === 'delta') onDelta(payload.text);
      else if (event === 'done') {
        finished = true;
        onDone(payload);
      } else if (event === 'error') {
        finished = true;
        onError(payload.message);
      }
    }
  } catch {
    if (signal?.aborted) return;
    finished = true;
    onError('응답을 받는 중에 연결이 끊겼어요.');
  }
  if (!finished && !signal?.aborted) onError('응답이 중간에 끝났어요.');
}

/** 최소 SSE 파서 (서버 쪽 src/agent/sse.js와 같은 규칙, 브라우저용 사본) */
async function* readEvents(stream) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true }).replace(/\r\n?/g, '\n');
    let i;
    while ((i = buffer.indexOf('\n\n')) !== -1) {
      const block = buffer.slice(0, i);
      buffer = buffer.slice(i + 2);
      let event = 'message';
      const data = [];
      for (const line of block.split('\n')) {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        else if (line.startsWith('data:')) data.push(line.slice(5).replace(/^ /, ''));
      }
      if (data.length) yield { event, data: data.join('\n') };
    }
  }
}

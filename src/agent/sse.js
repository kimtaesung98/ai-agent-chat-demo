/**
 * SSE(Server-Sent Events) 스트림을 { event, data } 단위로 읽는다.
 * - 이벤트는 빈 줄로 구분된다.
 * - data: 줄이 여러 개면 줄바꿈으로 이어 붙인다.
 * - 주석 줄(':'로 시작)과 알 수 없는 필드는 무시한다.
 *
 * @param {ReadableStream<Uint8Array>} stream
 * @returns {AsyncGenerator<{ event: string, data: string }>}
 */
export async function* parseSSE(stream) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      // \r\n 과 \r 도 줄바꿈으로 취급
      buffer = buffer.replace(/\r\n?/g, '\n');
      let boundary;
      while ((boundary = buffer.indexOf('\n\n')) !== -1) {
        const block = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        const parsed = parseBlock(block);
        if (parsed) yield parsed;
      }
    }
    buffer += decoder.decode();
    const tail = parseBlock(buffer.replace(/\r\n?/g, '\n').trim());
    if (tail) yield tail;
  } finally {
    reader.releaseLock();
  }
}

function parseBlock(block) {
  if (!block) return null;
  let event = 'message';
  const data = [];
  for (const line of block.split('\n')) {
    if (line === '' || line.startsWith(':')) continue;
    const colon = line.indexOf(':');
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? '' : line.slice(colon + 1);
    if (value.startsWith(' ')) value = value.slice(1);
    if (field === 'event') event = value;
    else if (field === 'data') data.push(value);
  }
  if (data.length === 0) return null;
  return { event, data: data.join('\n') };
}

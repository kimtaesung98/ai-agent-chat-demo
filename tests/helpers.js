import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { createApp } from '../src/server/app.js';

export const publicDir = fileURLToPath(new URL('../public', import.meta.url));

/** 앱을 임의 포트로 띄우고 { baseUrl, close } 를 돌려준다. */
export async function startApp(provider) {
  const server = http.createServer(createApp({ provider, publicDir }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    close: () =>
      new Promise((resolve) => {
        server.closeAllConnections();
        server.close(resolve);
      }),
  };
}

/** SSE 응답을 끝까지 읽어 [{ event, data, at }] 로 돌려준다. at = 도착 순서. */
export async function readSSE(res) {
  const events = [];
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of res.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let i;
    while ((i = buffer.indexOf('\n\n')) !== -1) {
      const block = buffer.slice(0, i);
      buffer = buffer.slice(i + 2);
      const event = /^event: (.*)$/m.exec(block)?.[1];
      const data = /^data: (.*)$/m.exec(block)?.[1];
      events.push({ event, data: JSON.parse(data), at: events.length });
    }
  }
  return events;
}

export function postChat(baseUrl, body) {
  return fetch(`${baseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

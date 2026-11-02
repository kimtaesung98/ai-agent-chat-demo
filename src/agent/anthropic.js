/**
 * Claude 제공자 — Messages API를 stream: true로 호출하고 SSE 이벤트를 인터페이스로 바꾼다.
 * 이벤트 순서: message_start → (content_block_start → content_block_delta* → content_block_stop)*
 *             → message_delta* → message_stop. ping·알 수 없는 이벤트는 무시한다.
 */
import { parseSSE } from './sse.js';
import { ProviderError, toUserMessage } from './errors.js';

const API_VERSION = '2023-06-01';

/**
 * @param {{
 *   apiKey: string,
 *   model: string,
 *   baseUrl?: string,
 *   maxTokens?: number,
 *   fetchImpl?: typeof fetch,
 * }} options
 */
export function createAnthropicProvider({
  apiKey,
  model,
  baseUrl = 'https://api.anthropic.com',
  maxTokens = 1024,
  fetchImpl = fetch,
}) {
  if (!apiKey) throw new Error('apiKey is required');

  return {
    name: 'anthropic',
    model,
    async *stream(messages, { signal } = {}) {
      let res;
      try {
        res = await fetchImpl(`${baseUrl}/v1/messages`, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': API_VERSION,
          },
          body: JSON.stringify({
            model,
            max_tokens: maxTokens,
            stream: true,
            messages: messages.map(({ role, content }) => ({ role, content })),
          }),
          signal,
        });
      } catch (err) {
        if (signal?.aborted) return;
        throw new ProviderError(toUserMessage({}), { code: 'network_error' });
      }

      if (!res.ok) {
        const type = await readErrorType(res);
        throw new ProviderError(toUserMessage({ status: res.status, type }), {
          status: res.status,
          code: type,
        });
      }

      let stopReason = 'end_turn';
      try {
        for await (const { event, data } of parseSSE(res.body)) {
          const payload = safeJson(data);
          if (!payload) continue;
          if (event === 'content_block_delta' && payload.delta?.type === 'text_delta') {
            yield { type: 'delta', text: payload.delta.text };
          } else if (event === 'message_delta' && payload.delta?.stop_reason) {
            stopReason = payload.delta.stop_reason;
          } else if (event === 'error') {
            const type = payload.error?.type;
            throw new ProviderError(toUserMessage({ type }), { code: type });
          } else if (event === 'message_stop') {
            break;
          }
          // ping, message_start, content_block_start/stop, 알 수 없는 이벤트 → 무시
        }
      } catch (err) {
        if (err instanceof ProviderError) throw err;
        if (signal?.aborted) return;
        throw new ProviderError(toUserMessage({}), { code: 'stream_error' });
      }

      if (signal?.aborted) return;
      yield { type: 'done', stopReason };
    },
  };
}

async function readErrorType(res) {
  try {
    const body = await res.json();
    return body?.error?.type;
  } catch {
    return undefined;
  }
}

function safeJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

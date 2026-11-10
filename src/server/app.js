/**
 * HTTP 라우터. 제공자는 주입받으며, 제공자 종류에 따라 분기하지 않는다 (src/server/README.md).
 */
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { validateChatRequest } from './validate.js';
import { trimToRecentTurns } from './context.js';
import { systemPromptFor } from './voice.js';
import { personaSystemPrompt } from './persona.js';
import { ProviderError } from '../agent/errors.js';

const MAX_BODY_BYTES = 1024 * 1024;
const GENERIC_ERROR = 'AI 응답을 받지 못했어요. 잠시 후 다시 시도해 주세요.';
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
};

/**
 * @param {{ provider: { name: string, model: string, stream: Function }, publicDir: string, log?: (line: string) => void }} deps
 * @returns {(req: import('node:http').IncomingMessage, res: import('node:http').ServerResponse) => Promise<void>}
 */
export function createApp({ provider, publicDir, log = () => {} }) {
  const root = path.resolve(publicDir);

  return async function handle(req, res) {
    const started = Date.now();
    // 'close'는 정상 종료와 클라이언트 중단 모두에서 발생 → 스트림이 끊긴 요청도 기록
    res.on('close', () => {
      const note = res.writableFinished ? '' : ' (client closed)';
      log(`${req.method} ${pathOf(req)} ${res.statusCode} ${Date.now() - started}ms${note}`);
    });

    try {
      const url = pathOf(req);
      if (url === '/api/chat') {
        if (req.method !== 'POST') return sendJson(res, 405, error('METHOD_NOT_ALLOWED', 'POST만 지원해요.'));
        return await handleChat(req, res, provider);
      }
      if (url === '/api/config') {
        if (req.method !== 'GET') return sendJson(res, 405, error('METHOD_NOT_ALLOWED', 'GET만 지원해요.'));
        return sendJson(res, 200, { provider: provider.name, model: provider.model });
      }
      if (req.method === 'GET' || req.method === 'HEAD') {
        return await serveStatic(res, root, url);
      }
      return sendJson(res, 404, error('NOT_FOUND', '찾을 수 없어요.'));
    } catch (err) {
      log(`unhandled error: ${err?.name ?? 'Error'}`);
      if (!res.headersSent) sendJson(res, 500, error('INTERNAL', '서버 오류가 발생했어요.'));
      else res.end();
    }
  };
}

async function handleChat(req, res, provider) {
  let body;
  try {
    body = JSON.parse(await readBody(req));
  } catch (err) {
    if (err?.code === 'TOO_LARGE') return sendJson(res, 413, error('TOO_LARGE', '요청이 너무 커요.'));
    return sendJson(res, 400, error('INVALID_JSON', '요청 본문이 올바른 JSON이 아니에요.'));
  }

  const result = validateChatRequest(body);
  if (!result.ok) return sendJson(res, 400, error(result.code, result.message));
  const messages = trimToRecentTurns(result.messages); // F-002 AC2

  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
    'x-accel-buffering': 'no',
  });
  res.flushHeaders();

  // 클라이언트가 끊으면 제공자 요청도 취소 (F-003 AC2의 서버 쪽 기반)
  const controller = new AbortController();
  res.on('close', () => {
    if (!res.writableEnded) controller.abort();
  });

  try {
    for await (const chunk of provider.stream(messages, { signal: controller.signal, system: systemPrompt(result) })) {
      if (controller.signal.aborted) break;
      if (chunk.type === 'delta') writeEvent(res, 'delta', { text: chunk.text });
      else if (chunk.type === 'done') writeEvent(res, 'done', { stopReason: chunk.stopReason });
    }
  } catch (err) {
    const message = err instanceof ProviderError ? err.userMessage : GENERIC_ERROR;
    if (!controller.signal.aborted) writeEvent(res, 'error', { message });
  } finally {
    if (!res.writableEnded) res.end();
  }
}

function writeEvent(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

async function serveStatic(res, root, url) {
  const relative = url === '/' ? 'index.html' : decodeURIComponent(url).replace(/^\/+/, '');
  const file = path.resolve(root, relative);
  // public/ 바깥 경로, README 같은 문서 파일은 제공하지 않음
  if (!file.startsWith(root + path.sep) || !MIME[path.extname(file)]) {
    return sendJson(res, 404, error('NOT_FOUND', '찾을 수 없어요.'));
  }
  try {
    const content = await readFile(file);
    res.writeHead(200, { 'content-type': MIME[path.extname(file)], 'cache-control': 'no-cache' });
    res.end(content);
  } catch {
    sendJson(res, 404, error('NOT_FOUND', '찾을 수 없어요.'));
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('too large'), { code: 'TOO_LARGE' }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function sendJson(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function error(code, message) {
  return { error: { code, message } };
}

function pathOf(req) {
  return new URL(req.url ?? '/', 'http://localhost').pathname;
}

/** 페르소나 다음에 말투 지시 (ADR-015·016). 둘 다 없으면 빈 문자열. Go chat.Request.SystemPrompt와 같다. */
function systemPrompt({ mode, persona }) {
  return [personaSystemPrompt(persona), systemPromptFor(mode)].filter(Boolean).join('\n\n');
}

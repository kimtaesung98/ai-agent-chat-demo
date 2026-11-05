/**
 * 서버를 모의 모드로 띄워 Go 계약 테스트(server/contract)를 실행한다 (SPEC.md F-009 AC2, F-010 AC1).
 * 실행: npm run test:contract       — Node 서버
 *       npm run test:contract:go    — Go 서버 (STATIC_DIR=../public)
 * Go 1.25 이상 필요.
 */
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const target = process.argv.includes('--go') ? 'go' : 'node';
const root = fileURLToPath(new URL('..', import.meta.url));
const serverDir = path.join(root, 'server');
const port = await freePort();
const baseUrl = `http://127.0.0.1:${port}`;

// 모의 모드 강제: API 키를 넘기지 않는다 (실제 Claude 호출 금지)
const env = { ...process.env, PORT: String(port) };
delete env.ANTHROPIC_API_KEY;

let server;
let tmp;
if (target === 'go') {
  tmp = mkdtempSync(path.join(os.tmpdir(), 'chatd-'));
  const bin = path.join(tmp, 'chatd');
  if ((await run('go', ['build', '-o', bin, './cmd/chatd'], serverDir, { ...process.env, CGO_ENABLED: '0' })) !== 0) {
    process.exit(1);
  }
  server = spawn(bin, [], { cwd: serverDir, env: { ...env, STATIC_DIR: path.join(root, 'public') }, stdio: ['ignore', 'pipe', 'inherit'] });
} else {
  server = spawn(process.execPath, ['src/server/index.js'], { cwd: root, env, stdio: ['ignore', 'pipe', 'inherit'] });
}
server.stdout.resume(); // 요청 로그는 버린다

let code = 1;
try {
  await waitForServer(baseUrl);
  console.log(`contract: ${target} 서버 (${baseUrl})`);
  code = await run('go', ['test', './contract', '-count=1', '-v', `-base-url=${baseUrl}`], serverDir);
} catch (err) {
  console.error(`contract: ${err.message}`);
} finally {
  server.kill();
  if (tmp) rmSync(tmp, { recursive: true, force: true });
}
process.exit(code);

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

async function waitForServer(url, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) throw new Error(`${target} 서버가 바로 종료됐어요`);
    try {
      const res = await fetch(`${url}/api/config`);
      if (res.ok) return;
    } catch {
      // 아직 뜨는 중
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`${target} 서버가 10초 안에 뜨지 않았어요`);
}

function run(cmd, args, cwd, childEnv = process.env) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd, env: childEnv, stdio: 'inherit' });
    child.on('error', (err) => {
      console.error(`contract: ${cmd} 실행 실패 (${err.message}) — Go 1.25 이상이 설치돼 있는지 확인해 주세요`);
      resolve(1);
    });
    child.on('exit', (c) => resolve(c ?? 1));
  });
}

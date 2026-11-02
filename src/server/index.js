/**
 * 진입점: 환경변수로 제공자를 만들고 서버를 띄운다.
 * 실행: npm start  (키가 없으면 모의 모드)
 */
import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { createApp } from './app.js';
import { describeMode } from './mode.js';
import { createProvider } from '../agent/index.js';

const publicDir = fileURLToPath(new URL('../../public', import.meta.url));
const port = Number(process.env.PORT) || 3000;

const provider = createProvider(process.env);
const app = createApp({ provider, publicDir, log: (line) => console.log(line) });
const server = http.createServer(app);

server.listen(port, () => {
  console.log(describeMode(provider));
  console.log(`AI Agent Chat → http://localhost:${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}

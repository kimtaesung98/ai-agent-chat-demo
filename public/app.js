/**
 * DOM 연결만 담당한다. 대화 로직은 chat-controller.js, 통신은 chat-client.js.
 * 응답 텍스트는 항상 textContent로 넣는다 (XSS 방지, public/README.md Agent Control).
 */
import { streamChat } from './chat-client.js';
import { createChatController } from './chat-controller.js';

const log = document.getElementById('log');
const emptyTemplate = document.getElementById('empty').cloneNode(true);
const newChatButton = document.getElementById('new-chat');
const form = document.getElementById('composer');
const input = document.getElementById('input');
const sendButton = document.getElementById('send');
const modeBadge = document.getElementById('mode');

let current = null; // 스트리밍 중인 에이전트 말풍선

const ui = {
  appendUser(text) {
    document.getElementById('empty')?.remove();
    addBubble('user', text);
  },
  startAssistant() {
    current = addBubble('assistant', '');
    current.classList.add('streaming');
  },
  appendDelta(text) {
    current.textContent += text;
    log.scrollTop = log.scrollHeight;
  },
  finishAssistant() {
    current?.classList.remove('streaming');
    current = null;
  },
  showError(message) {
    current.classList.remove('streaming');
    current.classList.add('error');
    current.textContent = message;
    current = null;
  },
  setBusy(isBusy) {
    input.disabled = isBusy;
    sendButton.disabled = isBusy;
    newChatButton.disabled = isBusy;
    if (!isBusy) input.focus();
  },
  clear() {
    current = null;
    log.replaceChildren(emptyTemplate.cloneNode(true));
    input.focus();
  },
};

const chat = createChatController({ ui, streamChat });

// F-002 AC3: 새 대화
newChatButton.addEventListener('click', () => chat.reset());

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const text = input.value;
  if (text.trim() === '') return; // F-001 AC3: 빈 메시지는 보내지 않음
  input.value = '';
  autoGrow();
  await chat.send(text);
});

input.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    form.requestSubmit();
  }
});
input.addEventListener('input', autoGrow);

function addBubble(role, text) {
  const el = document.createElement('div');
  el.className = `msg ${role}`;
  el.textContent = text;
  log.append(el);
  log.scrollTop = log.scrollHeight;
  return el;
}

function autoGrow() {
  input.style.height = 'auto';
  input.style.height = `${input.scrollHeight}px`;
}

// F-001 AC4: 화면 상단에 현재 모드 표시
fetch('/api/config')
  .then((res) => res.json())
  .then(({ provider, model }) => {
    modeBadge.dataset.provider = provider;
    modeBadge.textContent = provider === 'mock' ? '모의 모드' : `Claude · ${model}`;
  })
  .catch(() => {
    modeBadge.textContent = '서버 연결 안 됨';
  });

input.focus();

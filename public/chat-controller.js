/**
 * 대화 내역과 화면 상태를 관리한다. DOM은 ui 객체를 통해서만 다룬다 (테스트 가능성 유지).
 *
 * ui 인터페이스:
 *   appendUser(text)        사용자 말풍선 추가
 *   startAssistant()        빈 에이전트 말풍선 추가 (스트리밍 대상)
 *   appendDelta(text)       현재 에이전트 말풍선에 조각 이어 붙이기
 *   finishAssistant()       스트리밍 종료 표시
 *   showError(message)      현재 에이전트 말풍선을 오류 상태로 표시
 *   setBusy(isBusy)         입력창·전송 버튼 활성/비활성
 *
 * @param {{ ui: object, streamChat: Function }} deps
 */
export function createChatController({ ui, streamChat }) {
  /** @type {{ role: 'user' | 'assistant', content: string }[]} */
  const history = [];
  let busy = false;

  return {
    get history() {
      return history.map((m) => ({ ...m }));
    },
    get busy() {
      return busy;
    },

    /**
     * 메시지를 보낸다. 빈 메시지·응답 대기 중에는 아무것도 하지 않고 false를 돌려준다 (F-001 AC3).
     * @param {string} text
     * @returns {Promise<boolean>} 요청을 보냈으면 true
     */
    async send(text) {
      if (busy || typeof text !== 'string' || text.trim() === '') return false;

      busy = true;
      history.push({ role: 'user', content: text });
      ui.appendUser(text);
      ui.setBusy(true);
      ui.startAssistant();

      let reply = '';
      let failed = false;
      try {
        await streamChat({
          messages: history.map((m) => ({ ...m })),
          onDelta: (chunk) => {
            reply += chunk;
            ui.appendDelta(chunk);
          },
          onDone: () => {},
          onError: (message) => {
            failed = true;
            ui.showError(message);
          },
        });
      } finally {
        if (failed) {
          // 실패한 질문은 내역에서 빼서 다음 요청이 꼬이지 않게 한다 (재시도는 F-004)
          history.pop();
        } else {
          history.push({ role: 'assistant', content: reply });
          ui.finishAssistant();
        }
        busy = false;
        ui.setBusy(false); // F-001 AC2
      }
      return true;
    },
  };
}

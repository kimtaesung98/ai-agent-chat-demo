/**
 * 제공자 오류. userMessage는 화면에 그대로 보여도 안전한 문장이어야 한다.
 * 업스트림 원문, API 키, 요청 헤더를 넣지 않는다 (src/agent/README.md Agent Control).
 */
export class ProviderError extends Error {
  /**
   * @param {string} userMessage 사용자에게 보여 줄 문장
   * @param {{ status?: number, code?: string }} [details] 로그·분기용 정보 (비밀값 금지)
   */
  constructor(userMessage, details = {}) {
    super(userMessage);
    this.name = 'ProviderError';
    this.userMessage = userMessage;
    this.status = details.status;
    this.code = details.code;
  }
}

/** HTTP 상태 코드 또는 업스트림 오류 타입을 사용자용 문장으로 바꾼다. */
export function toUserMessage({ status, type } = {}) {
  if (status === 401 || type === 'authentication_error') {
    return 'AI 서비스 인증에 실패했어요. 운영자에게 API 키 설정을 확인해 달라고 알려 주세요.';
  }
  if (status === 429 || type === 'rate_limit_error') {
    return '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.';
  }
  if (status === 529 || type === 'overloaded_error') {
    return 'AI 서비스에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요.';
  }
  if (status === 400 || type === 'invalid_request_error') {
    return '요청을 처리할 수 없어요. 메시지를 줄이거나 새 대화로 시도해 주세요.';
  }
  return 'AI 응답을 받지 못했어요. 잠시 후 다시 시도해 주세요.';
}

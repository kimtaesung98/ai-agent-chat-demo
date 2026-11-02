/** 시작 로그에 표시할 모드 문구 (SPEC.md F-001 AC4). 비밀값은 포함하지 않는다. */
export function describeMode({ name, model }) {
  return name === 'mock'
    ? '모드: 모의(mock) — ANTHROPIC_API_KEY가 없어 모의 응답을 사용합니다'
    : `모드: Claude — 모델 ${model}`;
}

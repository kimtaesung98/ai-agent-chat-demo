import { createMockProvider } from './mock.js';
import { createAnthropicProvider } from './anthropic.js';

export const DEFAULT_MODEL = 'claude-sonnet-5-5';

/**
 * 환경변수로 제공자를 고른다. API 키가 없으면 모의 모드 (SPEC.md F-001 AC4).
 * @param {Record<string, string | undefined>} env
 */
export function createProvider(env = process.env) {
  const apiKey = env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) return createMockProvider();
  return createAnthropicProvider({
    apiKey,
    model: env.ANTHROPIC_MODEL?.trim() || DEFAULT_MODEL,
  });
}

export { ProviderError } from './errors.js';

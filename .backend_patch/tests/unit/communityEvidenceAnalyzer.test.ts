import { describe, expect, it, vi } from 'vitest';
import {
  analyzeCommunityEvidence,
} from '@/lib/community-analysis/analyzer';

const input = {
  contentItemId: 'item-1',
  institutionCode: 'peking-university' as const,
  institutionName: '北京大学' as const,
  platform: 'zhihu' as const,
  suggestedDimension: 'course' as const,
  sanitizedText: '课程节奏较快，但教师答疑和学习资源比较充分。',
};

describe('analyzeCommunityEvidence', () => {
  it('accepts only strict bounded JSON and keeps human review required', async () => {
    const aiCall = vi.fn().mockResolvedValue({
      content: JSON.stringify({
        institutionCode: 'peking-university',
        majorName: null,
        dimension: 'course',
        claim: '课程节奏较快',
        sentiment: { course: 'mixed' },
        informationValue: 8,
        credibility: 6.5,
        riskReasons: [],
        requiresHumanReview: true,
      }),
      model: 'deepseek-test',
      usage: {},
      latencyMs: 10,
    });

    const result = await analyzeCommunityEvidence(input, aiCall);

    expect(result.requiresHumanReview).toBe(true);
    expect(result).not.toHaveProperty('reviewStatus');
    expect(aiCall).toHaveBeenCalledWith(expect.objectContaining({
      modelEnvKey: 'DEEPSEEK_COMMUNITY_ANALYSIS_MODEL',
      temperature: 0,
      timeoutMs: 12_000,
      maxTokens: 500,
    }));
  });

  it('rejects markdown, invalid dimensions and out-of-range scores', async () => {
    const markdown = vi.fn().mockResolvedValue({
      content: '```json\n{"dimension":"course"}\n```',
      model: 'test',
      usage: {},
      latencyMs: 1,
    });
    await expect(analyzeCommunityEvidence(input, markdown)).rejects.toThrow();

    const invalid = vi.fn().mockResolvedValue({
      content: JSON.stringify({
        institutionCode: 'peking-university',
        majorName: null,
        dimension: 'medical',
        claim: '错误维度',
        sentiment: {},
        informationValue: 11,
        credibility: 6,
        riskReasons: [],
        requiresHumanReview: true,
      }),
      model: 'test',
      usage: {},
      latencyMs: 1,
    });
    await expect(analyzeCommunityEvidence(input, invalid)).rejects.toThrow();
  });

  it('propagates timeout without approving the evidence', async () => {
    const timeout = vi.fn().mockRejectedValue(new Error('timeout'));
    await expect(analyzeCommunityEvidence(input, timeout)).rejects.toThrow('timeout');
  });
});

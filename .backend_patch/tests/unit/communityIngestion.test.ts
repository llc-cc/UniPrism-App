import { describe, expect, it, vi } from 'vitest';
import {
  communityIngestionPayloadSchema,
  ingestCommunityEvidence,
} from '@/lib/content-ingestion/communityIngestion';

const usefulDocument = {
  externalId: 'answer-123-comment-1',
  url: 'https://www.zhihu.com/question/123/answer/456',
  title: '北京大学课程体验',
  text: '我在北京大学读书四年，大一课程作业较多，但老师和科研资源都很丰富。',
  dimension: 'course',
  discoveredAt: '2026-07-31T01:00:00.000Z',
  publishedAt: null,
  engagement: { likes: 12 },
};

const validPayload = {
  runId: 'pilot-20260731-001',
  institutionCode: 'peking-university',
  institutionName: '北京大学',
  platform: 'zhihu',
  query: '北京大学 课程 知乎',
  documents: [usefulDocument],
};

describe('community ingestion contract', () => {
  it('accepts only the Beijing University pilot and supported platforms', () => {
    expect(() => communityIngestionPayloadSchema.parse(validPayload)).not.toThrow();
    expect(() => communityIngestionPayloadSchema.parse({
      ...validPayload,
      institutionCode: 'tsinghua-university',
    })).toThrow();
    expect(() => communityIngestionPayloadSchema.parse({
      ...validPayload,
      platform: 'xiaohongshu',
    })).toThrow();
  });

  it('rejects URLs that do not belong to the selected platform', () => {
    expect(() => communityIngestionPayloadSchema.parse({
      ...validPayload,
      documents: [{
        ...usefulDocument,
        url: 'https://example.com/copied-comment',
      }],
    })).toThrow();
  });
});

describe('ingestCommunityEvidence', () => {
  it('stores useful evidence for review and counts rule-rejected noise', async () => {
    const persist = vi.fn().mockResolvedValue({
      itemId: 'item-1',
      action: 'created',
      version: 1,
    });
    const upsertAnalysis = vi.fn().mockResolvedValue({ id: 'analysis-1' });
    const updateBatch = vi.fn().mockResolvedValue({ id: 'batch-1' });
    const database = {
      contentSource: {
        upsert: vi.fn().mockResolvedValue({ id: 'source-1' }),
      },
      contentRightsSnapshot: {
        upsert: vi.fn().mockResolvedValue({ id: 'rights-1' }),
      },
      contentIngestionBatch: {
        create: vi.fn().mockResolvedValue({ id: 'batch-1' }),
        update: updateBatch,
      },
      communityEvidenceAnalysis: {
        upsert: upsertAnalysis,
      },
    };

    const result = await ingestCommunityEvidence(
      database as never,
      {
        ...validPayload,
        documents: [
          usefulDocument,
          {
            ...usefulDocument,
            externalId: 'noise-1',
            text: '哈哈哈哈',
          },
        ],
      },
      persist,
    );

    expect(result).toMatchObject({
      createdCount: 1,
      rejectedCount: 1,
      failedCount: 0,
    });
    expect(persist).toHaveBeenCalledWith(
      database,
      expect.objectContaining({ forceHumanReview: true }),
    );
    expect(upsertAnalysis).toHaveBeenCalledTimes(1);
    expect(updateBatch).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        status: 'completed',
        stageMetrics: expect.objectContaining({
          extracted: 2,
          ruleRejected: 1,
          pendingReview: 1,
        }),
      }),
    }));
  });
});

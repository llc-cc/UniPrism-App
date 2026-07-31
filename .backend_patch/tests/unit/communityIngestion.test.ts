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

const agentMetadata = {
  mode: 'agent',
  skillName: 'uniprism-university-community-crawler',
  skillVersion: 'uniprism-community-v1',
  plannedTasks: 14,
  completedTasks: 12,
  blockedTasks: 2,
  failedTasks: 0,
  steps: 48,
  pagesVisited: 30,
  duplicatesRemoved: 6,
  triggerSource: 'scheduled',
} as const;

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

  it('accepts bounded Agent audit metadata and rejects invalid counters', () => {
    expect(() => communityIngestionPayloadSchema.parse({
      ...validPayload,
      trigger: 'scheduled',
      agentMetadata,
    })).not.toThrow();
    expect(() => communityIngestionPayloadSchema.parse({
      ...validPayload,
      agentMetadata: { ...agentMetadata, steps: -1 },
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
    const sourceUpsert = vi.fn().mockResolvedValue({ id: 'source-1' });
    const updateSource = vi.fn().mockResolvedValue({ id: 'source-1' });
    const createBatch = vi.fn().mockResolvedValue({ id: 'batch-1' });
    const updateBatch = vi.fn().mockResolvedValue({ id: 'batch-1' });
    const database = {
      contentSource: {
        upsert: sourceUpsert,
        update: updateSource,
      },
      contentRightsSnapshot: {
        upsert: vi.fn().mockResolvedValue({ id: 'rights-1' }),
      },
      contentIngestionBatch: {
        findUnique: vi.fn().mockResolvedValue(null),
        create: createBatch,
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
        trigger: 'scheduled',
        agentMetadata,
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
    expect(sourceUpsert).toHaveBeenCalledWith(expect.objectContaining({
      create: expect.objectContaining({
        status: 'enabled',
        syncMode: 'scheduled',
        scheduleCron: '0 3 * * *',
      }),
      update: expect.objectContaining({
        status: 'enabled',
        syncMode: 'scheduled',
      }),
    }));
    expect(updateSource).toHaveBeenCalledWith({
      where: { id: 'source-1' },
      data: expect.objectContaining({ lastSuccessAt: expect.any(Date) }),
    });
    expect(upsertAnalysis).toHaveBeenCalledTimes(1);
    expect(createBatch).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ trigger: 'scheduled' }),
    }));
    expect(updateBatch).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        status: 'completed',
        stageMetrics: expect.objectContaining({
          extracted: 2,
          ruleRejected: 1,
          pendingReview: 1,
          agent: expect.objectContaining({
            skillVersion: 'uniprism-community-v1',
            steps: 48,
            pagesVisited: 30,
          }),
        }),
      }),
    }));
  });

  it('returns the completed batch when the crawler retries the same run id', async () => {
    const database = {
      contentSource: {
        upsert: vi.fn().mockResolvedValue({ id: 'source-1' }),
      },
      contentRightsSnapshot: {
        upsert: vi.fn().mockResolvedValue({ id: 'rights-1' }),
      },
      contentIngestionBatch: {
        findUnique: vi.fn().mockResolvedValue({
          id: 'batch-existing',
          status: 'completed',
          createdCount: 2,
          updatedCount: 0,
          unchangedCount: 3,
          rejectedCount: 1,
          failedCount: 0,
        }),
        create: vi.fn(),
      },
    };

    const result = await ingestCommunityEvidence(
      database as never,
      validPayload,
      vi.fn(),
    );

    expect(result).toMatchObject({
      batchId: 'batch-existing',
      createdCount: 2,
      unchangedCount: 3,
    });
    expect(database.contentIngestionBatch.create).not.toHaveBeenCalled();
  });
});

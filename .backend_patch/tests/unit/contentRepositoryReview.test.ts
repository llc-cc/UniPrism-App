import { describe, expect, it, vi } from 'vitest';
import { persistNormalizedContent } from '@/lib/content-ingestion/repository';
import type { NormalizedContentRecord } from '@/lib/content-ingestion/contracts';

function normalizedRecord(): NormalizedContentRecord {
  return {
    provider: 'zhihu-peking-university-public',
    externalId: 'comment-1',
    originalUrl: 'https://www.zhihu.com/question/1/answer/2',
    canonicalUrl: 'https://www.zhihu.com/question/1/answer/2',
    canonicalUrlHash: 'a'.repeat(64),
    originalTitle: '北京大学课程体验',
    normalizedTitle: '北京大学课程体验',
    excerpt: '课程压力较高，但教学资源丰富。',
    bodyText: '课程压力较高，但教学资源丰富。',
    contentType: 'community_comment',
    language: 'zh-CN',
    authors: [],
    tags: ['community', 'peking-university', 'course'],
    metrics: {},
    publishedAt: null,
    sourceUpdatedAt: null,
    rawPayloadHash: 'b'.repeat(64),
    contentHash: 'c'.repeat(64),
    cleanerVersion: 'community-cleaner-v1',
    policyVersion: 'community-public-review-v1',
    originalCharCount: 16,
    normalizedCharCount: 16,
    safetyFlags: [],
  };
}

describe('persistNormalizedContent forced review', () => {
  it('forces a stored community item into human review', async () => {
    const create = vi.fn().mockResolvedValue({
      id: 'item-1',
      currentVersion: 1,
    });
    const tx = {
      contentRightsSnapshot: {
        findUnique: vi.fn().mockResolvedValue({ status: 'allowed' }),
      },
      contentItem: {
        findUnique: vi.fn().mockResolvedValue(null),
        create,
      },
    };
    const database = {
      $transaction: vi.fn(async (callback: (client: typeof tx) => unknown) => callback(tx)),
    };

    await persistNormalizedContent(database as never, {
      sourceId: 'source-1',
      rightsSnapshotId: 'rights-1',
      normalized: normalizedRecord(),
      forceHumanReview: true,
    });

    expect(create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        reviewStatus: 'human_required',
        lifecycleStatus: 'review_required',
        riskLevel: 'community_unreviewed',
      }),
    }));
  });
});

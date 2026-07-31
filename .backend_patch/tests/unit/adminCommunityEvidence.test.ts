import { describe, expect, it, vi } from 'vitest';
import {
  listCommunityEvidence,
  reviewCommunityEvidence,
} from '@/lib/adminCommunityEvidence';

function databaseWithTransaction(item: Record<string, unknown>) {
  const tx = {
    communityEvidenceAnalysis: {
      findUnique: vi.fn().mockResolvedValue(item),
      update: vi.fn().mockResolvedValue({}),
    },
    contentItem: { update: vi.fn().mockResolvedValue({}) },
    contentDocument: { update: vi.fn().mockResolvedValue({}) },
    contentVersion: { create: vi.fn().mockResolvedValue({}) },
    auditLog: { create: vi.fn().mockResolvedValue({}) },
  };
  return {
    tx,
    database: {
      $transaction: vi.fn(async (callback) => callback(tx)),
    },
  };
}

const reviewItem = {
  contentItemId: 'item-1',
  updatedAt: new Date('2026-07-31T01:00:00.000Z'),
  platform: 'zhihu',
  dimension: 'course',
  contentItem: {
    id: 'item-1',
    currentVersion: 1,
    cleanerVersion: 'community-cleaner-v1',
    originalUrl: 'https://www.zhihu.com/question/1',
    document: {
      bodyText: '课程节奏较快，但老师会安排答疑并提供学习资源。',
    },
  },
};

describe('admin community evidence service', () => {
  it('lists sanitized evidence without account identity fields', async () => {
    const database = {
      communityEvidenceAnalysis: {
        count: vi.fn().mockResolvedValue(1),
        findMany: vi.fn().mockResolvedValue([{
          contentItemId: 'item-1',
          institutionName: '北京大学',
          platform: 'zhihu',
          dimension: 'course',
          qualityScore: 75,
          credibilityScore: 6.5,
          analysisStatus: 'ai_completed',
          claims: [{ text: '课程节奏较快' }],
          sentiment: { course: 'mixed' },
          updatedAt: new Date('2026-07-31T01:00:00.000Z'),
          contentItem: {
            originalUrl: 'https://www.zhihu.com/question/1',
            reviewStatus: 'human_required',
            createdAt: new Date('2026-07-31T00:30:00.000Z'),
            document: { bodyText: '已脱敏的课程体验正文' },
          },
        }]),
      },
    };

    const result = await listCommunityEvidence(
      { status: 'pending', page: 1, pageSize: 20 },
      database as never,
    );

    expect(result.items).toHaveLength(1);
    expect(JSON.stringify(result)).not.toMatch(/username|accountId|avatar|rawSnapshot/i);
  });

  it('approves evidence and writes an audit record', async () => {
    const { tx, database } = databaseWithTransaction(reviewItem);

    await reviewCommunityEvidence('item-1', {
      action: 'approve',
      expectedUpdatedAt: '2026-07-31T01:00:00.000Z',
      note: '内容与来源匹配',
    }, 'admin-1', database as never);

    expect(tx.contentItem.update).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        reviewStatus: 'approved',
        lifecycleStatus: 'approved',
      }),
    }));
    expect(tx.auditLog.create).toHaveBeenCalled();
  });

  it('rejects stale review writes', async () => {
    const { database } = databaseWithTransaction(reviewItem);

    await expect(reviewCommunityEvidence('item-1', {
      action: 'reject',
      expectedUpdatedAt: '2026-07-31T02:00:00.000Z',
    }, 'admin-1', database as never)).rejects.toMatchObject({
      code: 'CONFLICT',
      status: 409,
    });
  });

  it('cleans edited text and creates a new version before approval', async () => {
    const { tx, database } = databaseWithTransaction(reviewItem);

    await reviewCommunityEvidence('item-1', {
      action: 'edit_and_approve',
      expectedUpdatedAt: '2026-07-31T01:00:00.000Z',
      editedText: '课程体验很好，详细通知可以联系 13800138000 获取。',
    }, 'admin-1', database as never);

    expect(tx.contentDocument.update).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({
        bodyText: expect.not.stringContaining('13800138000'),
      }),
    }));
    expect(tx.contentVersion.create).toHaveBeenCalled();
  });
});

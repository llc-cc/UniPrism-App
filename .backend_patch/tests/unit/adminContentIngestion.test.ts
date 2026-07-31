import { describe, expect, it } from 'vitest';
import {
  classifyContentSource,
  getAdminContentIngestionDashboard,
  getAdminContentIngestionSourceDetail,
} from '@/lib/adminContentIngestion';

describe('getAdminContentIngestionDashboard', () => {
  it('aggregates sources and exposes only batch statistics', async () => {
    const now = new Date('2026-07-30T01:00:00.000Z');
    const database = {
      contentSource: {
        findMany: async () => [{
          id: 'source-1', code: 'peking-university-public-pages', displayName: '北京大学官方公开页面',
          sourceKind: 'official-university-public-page', sourceUrl: 'https://www.pku.edu.cn/',
          status: 'enabled', syncMode: 'scheduled', scheduleCron: null, nextSyncAt: null, lastSuccessAt: now,
          allowAiProcess: false, allowRecommend: false,
          _count: { items: 65, batches: 3 },
          batches: [{
            id: 'batch-1', trigger: 'scheduled', status: 'completed', fetchedCount: 25,
            createdCount: 12, updatedCount: 1, unchangedCount: 12, failedCount: 0,
            errorCode: null, errorMessage: null,
            stageMetrics: {
              agent: {
                skillVersion: 'uniprism-community-v1',
                completedTasks: 12,
                blockedTasks: 2,
                failedTasks: 0,
                steps: 48,
                pagesVisited: 30,
                duplicatesRemoved: 6,
              },
            },
            startedAt: now, completedAt: now, createdAt: now,
          }],
        }],
        count: async () => 1,
        findUnique: async () => null,
      },
      contentIngestionBatch: {
        count: async () => 0,
        findMany: async () => [{ fetchedCount: 25, createdCount: 12, updatedCount: 1, failedCount: 0 }],
      },
      contentItem: {
        count: async () => 65,
        groupBy: async () => [
          { sourceId: 'source-1', contentType: 'major', _count: { _all: 40 } },
          { sourceId: 'source-1', contentType: 'campus_activity', _count: { _all: 25 } },
        ],
      },
      contentDocument: { count: async () => 60 },
    } as never;

    const dashboard = await getAdminContentIngestionDashboard(database);

    expect(dashboard.summary).toEqual({
      sources: 1, enabledSources: 1, pausedSources: 1, abnormalSources: 1, runningBatches: 0,
      contentItems: 65, contentDocuments: 60, todayFetchedCount: 25, todayWrittenCount: 13, todayFailedCount: 0,
    });
    expect(dashboard.sources[0]).toMatchObject({
      code: 'peking-university-public-pages', contentItemCount: 65, domain: 'education', domainLabel: '高校与教育',
      contentScopes: [{ code: 'major', label: '专业与院系', count: 40 }, { code: 'campus_activity', label: '校园活动', count: 25 }],
      recentBatches: [{ fetchedCount: 25, createdCount: 12, unchangedCount: 12 }],
    });
    expect(dashboard.sources[0].recentBatches[0].agentMetrics).toEqual({
      skillVersion: 'uniprism-community-v1',
      completedTasks: 12,
      blockedTasks: 2,
      failedTasks: 0,
      steps: 48,
      pagesVisited: 30,
      duplicatesRemoved: 6,
    });
    expect(dashboard.sources[0].recentBatches[0]).not.toHaveProperty('bodyText');
  });

  it('returns source failures as a bounded admin summary without document payloads', async () => {
    const now = new Date('2026-07-30T01:00:00.000Z');
    const database = {
      contentSource: {
        findUnique: async () => ({
          id: 'source-1', code: 'peking-university-public-pages', displayName: '北京大学官方公开页面',
          sourceKind: 'official-university-public-page', sourceUrl: 'https://www.pku.edu.cn/',
          status: 'enabled', syncMode: 'scheduled', scheduleCron: '0 2 * * *', nextSyncAt: null, lastSuccessAt: now,
          allowAiProcess: false, allowRecommend: false, _count: { items: 65, batches: 1 },
          batches: [{
            id: 'batch-1', trigger: 'scheduled', status: 'partial', fetchedCount: 25,
            createdCount: 20, updatedCount: 0, unchangedCount: 0, failedCount: 5,
            errorCode: 'PARTIAL_DOCUMENT_FAILURE',
            errorMessage: JSON.stringify([{ url: 'https://example.edu.cn/private', message: '页面正文为空' }]),
            startedAt: now, completedAt: now, createdAt: now,
          }],
        }),
      },
      contentItem: {
        groupBy: async () => [{ contentType: 'student_community', _count: { _all: 65 } }],
      },
    } as never;

    const detail = await getAdminContentIngestionSourceDetail('peking-university-public-pages', database);

    expect(detail).toMatchObject({
      scheduleDescription: '自动 · 0 2 * * *', allowAiProcess: false,
      domain: 'education', contentScopes: [{ code: 'student_community', label: '学生社团', count: 65 }],
    });
    expect(detail?.failures).toEqual([expect.objectContaining({ errorCode: 'PARTIAL_DOCUMENT_FAILURE', failedCount: 5, message: '5 条内容未入库：页面正文为空' })]);
    expect(detail?.failures[0]).not.toHaveProperty('url');
    expect(detail?.recentBatches[0]).not.toHaveProperty('bodyText');
  });

  it('keeps future social and user content separate from university sources', () => {
    expect(classifyContentSource('official-university-public-page', 'pku')).toBe('education');
    expect(classifyContentSource('social-trend-platform', 'social-hot-list')).toBe('social_trends');
    expect(classifyContentSource('user-consented-profile', 'user-context')).toBe('user_context');
    expect(classifyContentSource('government-open-data', 'moe-catalog')).toBe('public_authority');
  });
});

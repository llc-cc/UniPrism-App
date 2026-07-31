import type { PrismaClient } from '@prisma/client';
import { prisma } from '@/lib/db';

export const CONTENT_SOURCE_DOMAINS = {
  education: '高校与教育',
  public_authority: '政府与权威目录',
  social_trends: '社会热点',
  user_context: '用户相关内容',
  research_career: '科研与职业数据',
  other: '其他来源',
} as const;

export type AdminContentSourceDomain = keyof typeof CONTENT_SOURCE_DOMAINS;

export type AdminContentScope = {
  code: string;
  label: string;
  count: number;
};

export type AdminContentIngestionBatch = {
  id: string;
  trigger: string;
  status: string;
  fetchedCount: number;
  createdCount: number;
  updatedCount: number;
  unchangedCount: number;
  failedCount: number;
  errorMessage: string | null;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
  agentMetrics: AdminAgentMetrics | null;
};

export type AdminAgentMetrics = {
  skillVersion: string;
  completedTasks: number;
  blockedTasks: number;
  failedTasks: number;
  steps: number;
  pagesVisited: number;
  duplicatesRemoved: number;
};

export type AdminContentIngestionSource = {
  id: string;
  code: string;
  displayName: string;
  sourceKind: string;
  sourceUrl: string | null;
  domain: AdminContentSourceDomain;
  domainLabel: string;
  contentScopes: AdminContentScope[];
  status: string;
  syncMode: string;
  scheduleCron: string | null;
  scheduleDescription: string;
  nextSyncAt: string | null;
  lastSuccessAt: string | null;
  allowAiProcess: boolean;
  allowRecommend: boolean;
  contentItemCount: number;
  batchCount: number;
  recentBatches: AdminContentIngestionBatch[];
};

export type AdminContentIngestionFailure = {
  batchId: string;
  occurredAt: string;
  errorCode: string | null;
  failedCount: number;
  message: string;
};

export type AdminContentIngestionSourceDetail = AdminContentIngestionSource & {
  failures: AdminContentIngestionFailure[];
};

export type AdminContentIngestionDashboard = {
  updatedAt: string;
  summary: {
    sources: number;
    enabledSources: number;
    pausedSources: number;
    abnormalSources: number;
    runningBatches: number;
    contentItems: number;
    contentDocuments: number;
    todayFetchedCount: number;
    todayWrittenCount: number;
    todayFailedCount: number;
  };
  sources: AdminContentIngestionSource[];
};

type DatabaseClient = Pick<PrismaClient, 'contentSource' | 'contentIngestionBatch' | 'contentItem' | 'contentDocument'>;

const CONTENT_SCOPE_LABELS: Record<string, string> = {
  major: '专业与院系',
  department: '院系信息',
  course: '课程信息',
  curriculum: '培养方案',
  campus_activity: '校园活动',
  student_community: '学生社团',
  admission: '招生与录取',
  accommodation: '住宿与校区',
  commute: '交通与通勤',
  employment: '就业与升学',
  school_news: '校园新闻',
  social_trend: '社会热点',
  user_interest: '用户兴趣',
  career: '职业信息',
  research: '科研资料',
};

/**
 * 来源领域与内容主题分开归类。旧数据根据 sourceKind/code 兼容识别；新来源仍应填写明确的 sourceKind。
 */
export function classifyContentSource(sourceKind: string, sourceCode: string): AdminContentSourceDomain {
  const fingerprint = `${sourceKind} ${sourceCode}`.toLowerCase();
  if (/(university|college|school|campus|education)/.test(fingerprint)) return 'education';
  if (/(government|ministry|authority|official-directory|\bmoe\b)/.test(fingerprint)) return 'public_authority';
  if (/(social|trend|news|media|community|zhihu|weibo|bilibili)/.test(fingerprint)) return 'social_trends';
  if (/(user|profile|personal|consent|interest)/.test(fingerprint)) return 'user_context';
  if (/(research|academic|occupation|career|metadata|openalex|crossref|arxiv|pubmed|esco|onet)/.test(fingerprint)) return 'research_career';
  return 'other';
}

function contentScopeLabel(contentType: string) {
  return CONTENT_SCOPE_LABELS[contentType] ?? `其他内容（${contentType}）`;
}

function mapContentScopes(rows: Array<{ contentType: string; _count: { _all: number } }>): AdminContentScope[] {
  return rows
    .map((row) => ({ code: row.contentType, label: contentScopeLabel(row.contentType), count: row._count._all }))
    .sort((left, right) => right.count - left.count || left.label.localeCompare(right.label, 'zh-CN'));
}

/**
 * 看板按中国自然日统计，避免服务器采用 UTC 时在北京时间凌晨展示到错误的“今日”数据。
 */
function getChinaDayStartUtc(now = new Date()) {
  const chinaOffsetMs = 8 * 60 * 60 * 1_000;
  const chinaNow = new Date(now.getTime() + chinaOffsetMs);
  return new Date(Date.UTC(
    chinaNow.getUTCFullYear(),
    chinaNow.getUTCMonth(),
    chinaNow.getUTCDate(),
  ) - chinaOffsetMs);
}

function describeSchedule(syncMode: string, scheduleCron: string | null) {
  if (syncMode === 'scheduled') return scheduleCron ? `自动 · ${scheduleCron}` : '自动 · 执行时间待配置';
  if (syncMode === 'manual') return '人工按需执行';
  if (syncMode === 'versioned_dataset') return '随数据集版本更新';
  return '按用户问题触发';
}

function summarizeError(errorMessage: string | null, failedCount: number) {
  if (!errorMessage) return failedCount > 0 ? '本批次存在未入库内容，请检查采集规则。' : '—';

  try {
    const parsed = JSON.parse(errorMessage) as Array<{ message?: unknown }>;
    if (Array.isArray(parsed)) {
      const messages = parsed
        .map((item) => typeof item?.message === 'string' ? item.message.trim() : '')
        .filter(Boolean)
        .slice(0, 2);
      const preview = messages.join('；');
      return `${failedCount} 条内容未入库${preview ? `：${preview.slice(0, 220)}` : ''}`;
    }
  } catch {
    // 部分旧任务保存的是普通文本，按受控长度展示即可。
  }

  return errorMessage.replace(/\s+/g, ' ').trim().slice(0, 240) || '本批次执行失败。';
}

function mapBatch(batch: {
  id: string;
  trigger: string;
  status: string;
  fetchedCount: number;
  createdCount: number;
  updatedCount: number;
  unchangedCount: number;
  failedCount: number;
  errorMessage: string | null;
  startedAt: Date | null;
  completedAt: Date | null;
  createdAt: Date;
  stageMetrics?: unknown;
}): AdminContentIngestionBatch {
  const agentMetrics = parseAgentMetrics(batch.stageMetrics);
  return {
    id: batch.id,
    trigger: batch.trigger,
    status: batch.status,
    fetchedCount: batch.fetchedCount,
    createdCount: batch.createdCount,
    updatedCount: batch.updatedCount,
    unchangedCount: batch.unchangedCount,
    failedCount: batch.failedCount,
    errorMessage: batch.errorMessage,
    agentMetrics,
    startedAt: batch.startedAt?.toISOString() ?? null,
    completedAt: batch.completedAt?.toISOString() ?? null,
    createdAt: batch.createdAt.toISOString(),
  };
}

function parseAgentMetrics(stageMetrics: unknown): AdminAgentMetrics | null {
  if (!stageMetrics || typeof stageMetrics !== 'object') return null;
  const agent = (stageMetrics as { agent?: unknown }).agent;
  if (!agent || typeof agent !== 'object') return null;
  const value = agent as Record<string, unknown>;
  const counters = [
    'completedTasks',
    'blockedTasks',
    'failedTasks',
    'steps',
    'pagesVisited',
    'duplicatesRemoved',
  ] as const;
  if (
    typeof value.skillVersion !== 'string'
    || counters.some((key) => (
      typeof value[key] !== 'number'
      || !Number.isInteger(value[key])
      || (value[key] as number) < 0
    ))
  ) {
    return null;
  }
  return {
    skillVersion: value.skillVersion.slice(0, 120),
    completedTasks: value.completedTasks as number,
    blockedTasks: value.blockedTasks as number,
    failedTasks: value.failedTasks as number,
    steps: value.steps as number,
    pagesVisited: value.pagesVisited as number,
    duplicatesRemoved: value.duplicatesRemoved as number,
  };
}

/**
 * 管理端采集看板的数据查询层。
 * 只聚合已存在的来源、批次和内容数据；不触发爬虫，也不暴露正文或密钥。
 */
export async function getAdminContentIngestionDashboard(
  database: DatabaseClient = prisma,
): Promise<AdminContentIngestionDashboard> {
  const [sources, sourceCount, enabledSourceCount, pausedSourceCount, abnormalSourceCount, runningBatchCount, contentItemCount, contentDocumentCount, todayBatches, contentScopeRows] = await Promise.all([
    database.contentSource.findMany({
      orderBy: [{ lastSuccessAt: 'desc' }, { updatedAt: 'desc' }],
      select: {
        id: true,
        code: true,
        displayName: true,
        sourceKind: true,
        sourceUrl: true,
        status: true,
        syncMode: true,
        scheduleCron: true,
        nextSyncAt: true,
        lastSuccessAt: true,
        allowAiProcess: true,
        allowRecommend: true,
        _count: {
          select: {
            items: true,
            batches: true,
          },
        },
        batches: {
          take: 8,
          orderBy: { createdAt: 'desc' },
          select: {
            id: true,
            trigger: true,
            status: true,
            fetchedCount: true,
            createdCount: true,
            updatedCount: true,
            unchangedCount: true,
            failedCount: true,
            errorMessage: true,
            stageMetrics: true,
            startedAt: true,
            completedAt: true,
            createdAt: true,
          },
        },
      },
    }),
    database.contentSource.count(),
    database.contentSource.count({ where: { status: 'enabled' } }),
    database.contentSource.count({ where: { status: 'paused' } }),
    database.contentSource.count({ where: { status: { in: ['blocked', 'error'] } } }),
    database.contentIngestionBatch.count({ where: { status: { in: ['pending', 'running'] } } }),
    database.contentItem.count(),
    database.contentDocument.count(),
    database.contentIngestionBatch.findMany({
      where: { createdAt: { gte: getChinaDayStartUtc() } },
      select: { fetchedCount: true, createdCount: true, updatedCount: true, failedCount: true },
    }),
    database.contentItem.groupBy({
      by: ['sourceId', 'contentType'],
      _count: { _all: true },
    }),
  ]);

  const todaySummary = todayBatches.reduce((summary, batch) => ({
    fetchedCount: summary.fetchedCount + batch.fetchedCount,
    writtenCount: summary.writtenCount + batch.createdCount + batch.updatedCount,
    failedCount: summary.failedCount + batch.failedCount,
  }), { fetchedCount: 0, writtenCount: 0, failedCount: 0 });
  const scopesBySource = new Map<string, AdminContentScope[]>();
  for (const row of contentScopeRows) {
    const existing = scopesBySource.get(row.sourceId) ?? [];
    existing.push({ code: row.contentType, label: contentScopeLabel(row.contentType), count: row._count._all });
    scopesBySource.set(row.sourceId, existing);
  }

  return {
    updatedAt: new Date().toISOString(),
    summary: {
      sources: sourceCount,
      enabledSources: enabledSourceCount,
      pausedSources: pausedSourceCount,
      abnormalSources: abnormalSourceCount,
      runningBatches: runningBatchCount,
      contentItems: contentItemCount,
      contentDocuments: contentDocumentCount,
      todayFetchedCount: todaySummary.fetchedCount,
      todayWrittenCount: todaySummary.writtenCount,
      todayFailedCount: todaySummary.failedCount,
    },
    sources: sources.map((source) => {
      const domain = classifyContentSource(source.sourceKind, source.code);
      const contentScopes = scopesBySource.get(source.id) ?? [];
      return {
        id: source.id,
        code: source.code,
        displayName: source.displayName,
        sourceKind: source.sourceKind,
        sourceUrl: source.sourceUrl,
        domain,
        domainLabel: CONTENT_SOURCE_DOMAINS[domain],
        contentScopes: contentScopes.sort((left, right) => right.count - left.count || left.label.localeCompare(right.label, 'zh-CN')),
        status: source.status,
        syncMode: source.syncMode,
        scheduleCron: source.scheduleCron,
        scheduleDescription: describeSchedule(source.syncMode, source.scheduleCron),
        nextSyncAt: source.nextSyncAt?.toISOString() ?? null,
        lastSuccessAt: source.lastSuccessAt?.toISOString() ?? null,
        allowAiProcess: source.allowAiProcess,
        allowRecommend: source.allowRecommend,
        contentItemCount: source._count.items,
        batchCount: source._count.batches,
        recentBatches: source.batches.map(mapBatch),
      };
    }),
  };
}

/**
 * 数据源详情只返回运行元数据、批次统计和受控长度的失败摘要；不返回正文、令牌或原始抓取载荷。
 */
export async function getAdminContentIngestionSourceDetail(
  sourceCode: string,
  database: DatabaseClient = prisma,
): Promise<AdminContentIngestionSourceDetail | null> {
  const source = await database.contentSource.findUnique({
    where: { code: sourceCode },
    select: {
      id: true,
      code: true,
      displayName: true,
      sourceKind: true,
      sourceUrl: true,
      status: true,
      syncMode: true,
      scheduleCron: true,
      nextSyncAt: true,
      lastSuccessAt: true,
      allowAiProcess: true,
      allowRecommend: true,
      _count: { select: { items: true, batches: true } },
      batches: {
        take: 50,
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          trigger: true,
          status: true,
          fetchedCount: true,
          createdCount: true,
          updatedCount: true,
          unchangedCount: true,
          failedCount: true,
          errorCode: true,
          errorMessage: true,
          stageMetrics: true,
          startedAt: true,
          completedAt: true,
          createdAt: true,
        },
      },
    },
  });
  if (!source) return null;

  const contentScopeRows = await database.contentItem.groupBy({
    by: ['contentType'],
    where: { sourceId: source.id },
    _count: { _all: true },
  });

  const recentBatches = source.batches.map(mapBatch);
  const domain = classifyContentSource(source.sourceKind, source.code);
  return {
    id: source.id,
    code: source.code,
    displayName: source.displayName,
    sourceKind: source.sourceKind,
    sourceUrl: source.sourceUrl,
    domain,
    domainLabel: CONTENT_SOURCE_DOMAINS[domain],
    contentScopes: mapContentScopes(contentScopeRows),
    status: source.status,
    syncMode: source.syncMode,
    scheduleCron: source.scheduleCron,
    scheduleDescription: describeSchedule(source.syncMode, source.scheduleCron),
    nextSyncAt: source.nextSyncAt?.toISOString() ?? null,
    lastSuccessAt: source.lastSuccessAt?.toISOString() ?? null,
    allowAiProcess: source.allowAiProcess,
    allowRecommend: source.allowRecommend,
    contentItemCount: source._count.items,
    batchCount: source._count.batches,
    recentBatches,
    failures: source.batches
      .filter((batch) => batch.failedCount > 0 || batch.status === 'failed' || batch.status === 'partial')
      .map((batch) => ({
        batchId: batch.id,
        occurredAt: (batch.completedAt ?? batch.createdAt).toISOString(),
        errorCode: batch.errorCode,
        failedCount: batch.failedCount,
        message: summarizeError(batch.errorMessage, batch.failedCount),
      })),
  };
}

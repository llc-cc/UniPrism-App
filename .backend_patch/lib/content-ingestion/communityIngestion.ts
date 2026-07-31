import type { PrismaClient } from '@prisma/client';
import { z } from 'zod';
import { cleanCommunityEvidence } from './communityCleaner';
import {
  COMMUNITY_PLATFORMS,
  type CommunityPlatform,
} from './communityContracts';
import {
  getCommunitySource,
  isAllowedCommunityUrl,
} from './communitySources';
import { normalizeContentRecord } from './normalizer';
import {
  persistNormalizedContent,
  type PersistNormalizedContentInput,
  type PersistNormalizedContentResult,
} from './repository';

export const COMMUNITY_DIMENSIONS = [
  'school',
  'major',
  'course',
  'employment',
  'dormitory',
  'cafeteria',
  'student_club',
] as const;

const communityDocumentSchema = z.object({
  externalId: z.string().trim().min(1).max(191),
  url: z.string().url().max(8_192),
  title: z.string().trim().min(1).max(2_000),
  text: z.string().trim().min(1).max(100_000),
  dimension: z.enum(COMMUNITY_DIMENSIONS),
  discoveredAt: z.string().datetime(),
  publishedAt: z.string().datetime().nullable().default(null),
  engagement: z.record(
    z.string().max(40),
    z.union([z.number().finite(), z.string().max(120), z.boolean()]),
  ).default({}),
}).strict();

const communityAgentMetadataSchema = z.object({
  mode: z.literal('agent'),
  skillName: z.string().trim().min(1).max(120),
  skillVersion: z.string().trim().min(1).max(120),
  plannedTasks: z.number().int().min(0).max(10_000),
  completedTasks: z.number().int().min(0).max(10_000),
  blockedTasks: z.number().int().min(0).max(10_000),
  failedTasks: z.number().int().min(0).max(10_000),
  steps: z.number().int().min(0).max(1_000_000),
  pagesVisited: z.number().int().min(0).max(1_000_000),
  duplicatesRemoved: z.number().int().min(0).max(1_000_000),
  triggerSource: z.enum(['manual', 'scheduled']),
}).strict();

export const communityIngestionPayloadSchema = z.object({
  runId: z.string().trim().min(8).max(191),
  institutionCode: z.literal('peking-university'),
  institutionName: z.literal('北京大学'),
  platform: z.enum(COMMUNITY_PLATFORMS),
  query: z.string().trim().min(2).max(300),
  trigger: z.enum(['manual', 'scheduled']).default('manual'),
  agentMetadata: communityAgentMetadataSchema.optional(),
  documents: z.array(communityDocumentSchema).min(1).max(50),
}).strict().superRefine((payload, context) => {
  payload.documents.forEach((document, index) => {
    if (!isAllowedCommunityUrl(payload.platform, document.url)) {
      context.addIssue({
        code: 'custom',
        path: ['documents', index, 'url'],
        message: 'Document URL does not belong to the selected platform.',
      });
    }
  });
});

export type CommunityIngestionPayload = z.infer<
  typeof communityIngestionPayloadSchema
>;

type PersistFunction = (
  prisma: PrismaClient,
  input: PersistNormalizedContentInput,
) => Promise<PersistNormalizedContentResult>;
type EnqueueAnalysisFunction = (
  contentItemId: string,
  cleanerVersion: string,
) => Promise<unknown>;

async function ensureCommunitySource(
  prisma: PrismaClient,
  platform: CommunityPlatform,
  trigger: 'manual' | 'scheduled',
) {
  const definition = getCommunitySource(platform);
  const scheduled = trigger === 'scheduled';
  const source = await prisma.contentSource.upsert({
    where: { code: definition.code },
    create: {
      code: definition.code,
      displayName: definition.displayName,
      sourceKind: 'community_public',
      status: scheduled ? 'enabled' : 'paused',
      syncMode: scheduled ? 'scheduled' : 'manual',
      scheduleCron: scheduled ? '0 3 * * *' : null,
      allowStoreMetadata: true,
      allowStoreExcerpt: true,
      allowStoreBody: true,
      allowStoreRawSnapshot: false,
      allowAiProcess: true,
      allowRecommend: false,
      allowPush: false,
      policyVersion: definition.policy.policyVersion,
      sourceUrl: definition.sourceUrl,
    },
    update: {
      displayName: definition.displayName,
      // 人工补测不能把已经启用的定时来源降级为暂停状态。
      ...(scheduled ? {
        status: 'enabled' as const,
        syncMode: 'scheduled' as const,
        scheduleCron: '0 3 * * *',
      } : {}),
      allowAiProcess: true,
      allowRecommend: false,
      allowPush: false,
      policyVersion: definition.policy.policyVersion,
    },
    select: { id: true },
  });
  const rights = await prisma.contentRightsSnapshot.upsert({
    where: {
      sourceId_policyVersion: {
        sourceId: source.id,
        policyVersion: definition.policy.policyVersion,
      },
    },
    create: {
      sourceId: source.id,
      policyVersion: definition.policy.policyVersion,
      status: 'allowed',
      allowStoreMetadata: true,
      allowStoreExcerpt: true,
      allowStoreBody: true,
      allowStoreRawSnapshot: false,
      allowAiProcess: true,
      allowRecommend: false,
      allowPush: false,
      evidenceType: 'public_page_policy',
      note: '仅保存匿名公开页面经脱敏后的证据；首批必须人工审核。',
      effectiveAt: new Date(),
    },
    update: {
      allowAiProcess: true,
      allowRecommend: false,
      allowPush: false,
    },
    select: { id: true },
  });
  return { source, rights, definition };
}

/**
 * 社区入库只保存规则清洗后的证据；明确垃圾仅计数，原始文本不会落库。
 */
export async function ingestCommunityEvidence(
  prisma: PrismaClient,
  input: CommunityIngestionPayload,
  persist: PersistFunction = persistNormalizedContent,
  enqueueAnalysis?: EnqueueAnalysisFunction,
) {
  const payload = communityIngestionPayloadSchema.parse(input);
  const { source, rights, definition } = await ensureCommunitySource(
    prisma,
    payload.platform,
    payload.trigger,
  );
  const idempotencyKey = `community:${payload.runId}:${payload.platform}`;
  const existingBatch = await prisma.contentIngestionBatch.findUnique({
    where: { idempotencyKey },
    select: {
      id: true,
      status: true,
      createdCount: true,
      updatedCount: true,
      unchangedCount: true,
      rejectedCount: true,
      failedCount: true,
    },
  });
  if (
    existingBatch
    && (existingBatch.status === 'completed' || existingBatch.status === 'partial')
  ) {
    return {
      batchId: existingBatch.id,
      status: existingBatch.status,
      createdCount: existingBatch.createdCount,
      updatedCount: existingBatch.updatedCount,
      unchangedCount: existingBatch.unchangedCount,
      rejectedCount: existingBatch.rejectedCount,
      failedCount: existingBatch.failedCount,
    };
  }
  if (existingBatch) {
    throw new Error('COMMUNITY_INGESTION_ALREADY_RUNNING');
  }
  const batch = await prisma.contentIngestionBatch.create({
    data: {
      sourceId: source.id,
      trigger: payload.trigger,
      // Python runId 已包含分批序号；固定键使网络重试不会重复创建采集批次。
      idempotencyKey,
      status: 'running',
      requestedCount: payload.documents.length,
      fetchedCount: payload.documents.length,
      cleanerVersion: 'community-cleaner-v1',
      policyVersion: definition.policy.policyVersion,
      startedAt: new Date(),
    },
    select: { id: true },
  });

  let createdCount = 0;
  let updatedCount = 0;
  let unchangedCount = 0;
  let rejectedCount = 0;
  let failedCount = 0;

  for (const document of payload.documents) {
    try {
      const cleaned = cleanCommunityEvidence({
        title: document.title,
        text: document.text,
        platform: payload.platform,
      });
      if (cleaned.decision === 'rejected') {
        rejectedCount += 1;
        continue;
      }

      const normalized = normalizeContentRecord({
        provider: definition.code,
        externalId: document.externalId,
        title: document.title,
        excerpt: cleaned.sanitizedText.slice(0, 800),
        bodyText: cleaned.sanitizedText,
        url: document.url,
        contentType: 'community_comment',
        language: 'zh-CN',
        authors: [],
        tags: [
          'community',
          payload.institutionCode,
          payload.platform,
          document.dimension,
        ],
        metrics: document.engagement,
        publishedAt: document.publishedAt,
        sourceUpdatedAt: document.discoveredAt,
        rawPayload: {
          externalId: document.externalId,
          url: document.url,
          dimension: document.dimension,
          discoveredAt: document.discoveredAt,
        },
      }, definition.policy, 'community-cleaner-v1');
      const persisted = await persist(prisma, {
        sourceId: source.id,
        rightsSnapshotId: rights.id,
        normalized,
        forceHumanReview: true,
      });
      if (persisted.action === 'created') createdCount += 1;
      if (persisted.action === 'updated') updatedCount += 1;
      if (persisted.action === 'unchanged') unchangedCount += 1;

      await prisma.communityEvidenceAnalysis.upsert({
        where: { contentItemId: persisted.itemId },
        create: {
          contentItemId: persisted.itemId,
          institutionCode: payload.institutionCode,
          institutionName: payload.institutionName,
          platform: payload.platform,
          dimension: document.dimension,
          qualityScore: cleaned.qualityScore,
          similarityHash: cleaned.similarityHash,
          spamSignals: cleaned.spamSignals,
          privacyFlags: cleaned.privacyFlags,
        },
        update: {
          dimension: document.dimension,
          qualityScore: cleaned.qualityScore,
          similarityHash: cleaned.similarityHash,
          spamSignals: cleaned.spamSignals,
          privacyFlags: cleaned.privacyFlags,
          analysisStatus: 'rules_passed',
        },
      });
      if (enqueueAnalysis) {
        await enqueueAnalysis(persisted.itemId, 'community-cleaner-v1');
      }
    } catch {
      failedCount += 1;
    }
  }

  const status = failedCount > 0 ? 'partial' : 'completed';
  const pendingReview = createdCount + updatedCount + unchangedCount;
  await prisma.contentIngestionBatch.update({
    where: { id: batch.id },
    data: {
      status,
      createdCount,
      updatedCount,
      unchangedCount,
      rejectedCount,
      failedCount,
      stageMetrics: {
        extracted: payload.documents.length,
        ruleRejected: rejectedCount,
        pendingReview,
        ...(payload.agentMetadata ? { agent: payload.agentMetadata } : {}),
      },
      completedAt: new Date(),
    },
  });
  if (failedCount === 0) {
    await prisma.contentSource.update({
      where: { id: source.id },
      data: { lastSuccessAt: new Date() },
    });
  }

  return {
    batchId: batch.id,
    status,
    createdCount,
    updatedCount,
    unchangedCount,
    rejectedCount,
    failedCount,
  };
}

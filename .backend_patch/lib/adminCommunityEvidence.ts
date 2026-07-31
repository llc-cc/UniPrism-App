import { z } from 'zod';
import { cleanCommunityEvidence } from './content-ingestion/communityCleaner';

export const communityEvidenceListQuerySchema = z.object({
  status: z.enum(['pending', 'approved', 'rejected', 'all']).default('pending'),
  platform: z.enum(['zhihu', 'tieba']).optional(),
  dimension: z.enum([
    'school',
    'major',
    'course',
    'employment',
    'dormitory',
    'cafeteria',
    'student_club',
  ]).optional(),
  query: z.string().trim().max(100).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(20).default(20),
}).strict();

export const communityEvidenceReviewSchema = z.object({
  action: z.enum(['approve', 'reject', 'edit_and_approve']),
  expectedUpdatedAt: z.string().datetime(),
  editedText: z.string().trim().min(8).max(20_000).optional(),
  note: z.string().trim().max(1_000).optional(),
}).strict().superRefine((value, context) => {
  if (value.action === 'edit_and_approve' && !value.editedText) {
    context.addIssue({
      code: 'custom',
      path: ['editedText'],
      message: '编辑后通过必须提供正文。',
    });
  }
});

export type CommunityEvidenceListQuery = z.infer<
  typeof communityEvidenceListQuerySchema
>;
export type CommunityEvidenceReviewInput = z.infer<
  typeof communityEvidenceReviewSchema
>;

export class CommunityReviewError extends Error {
  constructor(
    public readonly code:
      | 'NOT_FOUND'
      | 'CONFLICT'
      | 'VALIDATION_ERROR',
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = 'CommunityReviewError';
  }
}

type CommunityEvidenceDatabase = {
  communityEvidenceAnalysis: {
    count(args: unknown): Promise<number>;
    findMany(args: unknown): Promise<Array<Record<string, any>>>;
  };
};

type CommunityReviewTransaction = {
  communityEvidenceAnalysis: {
    findUnique(args: unknown): Promise<Record<string, any> | null>;
    update(args: unknown): Promise<unknown>;
  };
  contentItem: { update(args: unknown): Promise<unknown> };
  contentDocument: { update(args: unknown): Promise<unknown> };
  contentVersion: { create(args: unknown): Promise<unknown> };
  auditLog: { create(args: unknown): Promise<unknown> };
};

type CommunityReviewDatabase = {
  $transaction<T>(
    callback: (transaction: CommunityReviewTransaction) => Promise<T>,
  ): Promise<T>;
};

function reviewStatusFilter(status: CommunityEvidenceListQuery['status']) {
  if (status === 'pending') return 'human_required';
  if (status === 'approved') return 'approved';
  if (status === 'rejected') return 'rejected';
  return undefined;
}

/** 列表只投影脱敏正文和审核字段，不读取作者账号、头像或原始快照。 */
export async function listCommunityEvidence(
  rawQuery: CommunityEvidenceListQuery,
  database: CommunityEvidenceDatabase,
) {
  const query = communityEvidenceListQuerySchema.parse(rawQuery);
  const reviewStatus = reviewStatusFilter(query.status);
  const where = {
    ...(query.platform ? { platform: query.platform } : {}),
    ...(query.dimension ? { dimension: query.dimension } : {}),
    contentItem: {
      ...(reviewStatus ? { reviewStatus } : {}),
      ...(query.query ? {
        OR: [
          { normalizedTitle: { contains: query.query } },
          { document: { bodyText: { contains: query.query } } },
        ],
      } : {}),
    },
  };
  const [total, rows] = await Promise.all([
    database.communityEvidenceAnalysis.count({ where }),
    database.communityEvidenceAnalysis.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      skip: (query.page - 1) * query.pageSize,
      take: query.pageSize,
      select: {
        contentItemId: true,
        institutionName: true,
        majorName: true,
        platform: true,
        dimension: true,
        qualityScore: true,
        credibilityScore: true,
        duplicateClusterId: true,
        sentiment: true,
        claims: true,
        analysisStatus: true,
        privacyFlags: true,
        spamSignals: true,
        updatedAt: true,
        contentItem: {
          select: {
            originalUrl: true,
            reviewStatus: true,
            createdAt: true,
            document: { select: { bodyText: true } },
          },
        },
      },
    }),
  ]);

  return {
    page: query.page,
    pageSize: query.pageSize,
    total,
    items: rows.map((row) => ({
      contentItemId: row.contentItemId,
      institutionName: row.institutionName,
      majorName: row.majorName ?? null,
      platform: row.platform,
      dimension: row.dimension,
      sanitizedText: row.contentItem.document?.bodyText ?? '',
      qualityScore: row.qualityScore,
      credibilityScore: row.credibilityScore === null
        ? null
        : Number(row.credibilityScore),
      duplicateClusterId: row.duplicateClusterId ?? null,
      sentiment: row.sentiment ?? null,
      claims: row.claims ?? null,
      analysisStatus: row.analysisStatus,
      privacyFlags: row.privacyFlags ?? [],
      spamSignals: row.spamSignals ?? [],
      sourceUrl: row.contentItem.originalUrl,
      collectedAt: row.contentItem.createdAt.toISOString(),
      reviewStatus: row.contentItem.reviewStatus,
      updatedAt: row.updatedAt.toISOString(),
    })),
  };
}

/**
 * 审核在单个事务内校验版本并写审计记录，避免两个管理员互相覆盖。
 */
export async function reviewCommunityEvidence(
  itemId: string,
  rawInput: CommunityEvidenceReviewInput,
  actorUserId: string,
  database: CommunityReviewDatabase,
) {
  const input = communityEvidenceReviewSchema.parse(rawInput);
  return database.$transaction(async (transaction) => {
    const analysis = await transaction.communityEvidenceAnalysis.findUnique({
      where: { contentItemId: itemId },
      include: {
        contentItem: {
          include: { document: true },
        },
      },
    });
    if (!analysis?.contentItem) {
      throw new CommunityReviewError(
        'NOT_FOUND',
        '待审核内容不存在。',
        404,
      );
    }
    if (analysis.updatedAt.toISOString() !== input.expectedUpdatedAt) {
      throw new CommunityReviewError(
        'CONFLICT',
        '该内容已被其他管理员更新，请刷新后重试。',
        409,
      );
    }

    const approved = input.action !== 'reject';
    let cleanedEdit: ReturnType<typeof cleanCommunityEvidence> | null = null;
    if (input.action === 'edit_and_approve') {
      cleanedEdit = cleanCommunityEvidence({
        title: '管理员编辑内容',
        text: input.editedText!,
        platform: analysis.platform,
      });
      if (cleanedEdit.decision === 'rejected') {
        throw new CommunityReviewError(
          'VALIDATION_ERROR',
          '编辑后的正文仍不符合清洗规则。',
          400,
        );
      }
      if (!analysis.contentItem.document) {
        throw new CommunityReviewError(
          'NOT_FOUND',
          '内容正文不存在。',
          404,
        );
      }
      const nextVersion = analysis.contentItem.currentVersion + 1;
      await transaction.contentDocument.update({
        where: { contentItemId: itemId },
        data: {
          bodyText: cleanedEdit.sanitizedText,
          normalizedCharCount: cleanedEdit.sanitizedText.length,
          safetyFlags: cleanedEdit.privacyFlags,
        },
      });
      await transaction.contentVersion.create({
        data: {
          contentItemId: itemId,
          version: nextVersion,
          contentHash: cleanedEdit.contentHash,
          cleanerVersion: analysis.contentItem.cleanerVersion,
          policyVersion: 'community-public-review-v1',
          title: '管理员审核编辑',
          excerpt: cleanedEdit.sanitizedText.slice(0, 800),
          changedFields: ['bodyText'],
          changeReason: 'admin_edit_and_approve',
        },
      });
      await transaction.contentItem.update({
        where: { id: itemId },
        data: {
          contentHash: cleanedEdit.contentHash,
          excerpt: cleanedEdit.sanitizedText.slice(0, 800),
          currentVersion: nextVersion,
          reviewStatus: 'approved',
          lifecycleStatus: 'approved',
          riskLevel: 'admin_reviewed',
        },
      });
    } else {
      await transaction.contentItem.update({
        where: { id: itemId },
        data: {
          reviewStatus: approved ? 'approved' : 'rejected',
          lifecycleStatus: approved ? 'approved' : 'rejected',
          riskLevel: approved ? 'admin_reviewed' : 'admin_rejected',
        },
      });
    }

    await transaction.communityEvidenceAnalysis.update({
      where: { contentItemId: itemId },
      data: {
        analysisStatus: approved ? 'approved' : 'rejected',
        reviewerUserId: actorUserId,
        reviewedAt: new Date(),
        reviewNote: input.note ?? null,
        ...(cleanedEdit ? {
          qualityScore: cleanedEdit.qualityScore,
          similarityHash: cleanedEdit.similarityHash,
          privacyFlags: cleanedEdit.privacyFlags,
          spamSignals: cleanedEdit.spamSignals,
        } : {}),
      },
    });
    await transaction.auditLog.create({
      data: {
        actorUserId,
        action: `community_evidence.${input.action}`,
        resourceType: 'community_evidence',
        resourceId: itemId,
        metadata: {
          note: input.note ?? null,
          edited: Boolean(cleanedEdit),
        },
      },
    });
    return {
      contentItemId: itemId,
      reviewStatus: approved ? 'approved' : 'rejected',
    };
  });
}

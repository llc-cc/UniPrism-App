import {
  Prisma,
  type PrismaClient,
} from '@prisma/client';
import type { NormalizedContentRecord } from './contracts';

export type PersistNormalizedContentInput = {
  sourceId: string;
  rightsSnapshotId: string;
  normalized: NormalizedContentRecord;
  forceHumanReview?: boolean;
};

export type PersistNormalizedContentResult = {
  itemId: string;
  action: 'created' | 'updated' | 'unchanged';
  version: number;
};

type TransactionClient = Prisma.TransactionClient;
type DatabaseClient = Pick<PrismaClient, '$transaction'>;

function jsonValue(
  value: Record<string, string | number | boolean> | string[],
): Prisma.InputJsonValue {
  return value as Prisma.InputJsonValue;
}

async function persistInTransaction(
  tx: TransactionClient,
  input: PersistNormalizedContentInput,
): Promise<PersistNormalizedContentResult> {
  const { normalized } = input;
  const now = new Date();
  const rights = await tx.contentRightsSnapshot.findUnique({
    where: { id: input.rightsSnapshotId },
    select: { status: true },
  });
  if (!rights) {
    throw new Error('Content rights snapshot was not found.');
  }
  // 社区首批证据即使规则检查通过也必须人工复核，不能沿用普通内容的机器通过状态。
  const reviewStatus = input.forceHumanReview || normalized.safetyFlags.length > 0
    ? 'human_required' as const
    : rights.status === 'allowed'
      ? 'machine_passed' as const
      : 'pending' as const;
  const lifecycleStatus = input.forceHumanReview || normalized.safetyFlags.length > 0
    ? 'review_required' as const
    : 'normalized' as const;
  const riskLevel = input.forceHumanReview
    ? 'community_unreviewed'
    : normalized.safetyFlags.length > 0
      ? 'flagged'
      : 'machine_checked';
  const existing = await tx.contentItem.findUnique({
    where: {
      sourceId_externalId: {
        sourceId: input.sourceId,
        externalId: normalized.externalId,
      },
    },
    select: {
      id: true,
      contentHash: true,
      currentVersion: true,
    },
  });

  if (!existing) {
    const created = await tx.contentItem.create({
      data: {
        sourceId: input.sourceId,
        externalId: normalized.externalId,
        originalUrl: normalized.originalUrl,
        canonicalUrl: normalized.canonicalUrl,
        canonicalUrlHash: normalized.canonicalUrlHash,
        originalTitle: normalized.originalTitle,
        normalizedTitle: normalized.normalizedTitle,
        excerpt: normalized.excerpt,
        contentType: normalized.contentType,
        language: normalized.language,
        authors: jsonValue(normalized.authors),
        tags: jsonValue(normalized.tags),
        metrics: jsonValue(normalized.metrics),
        rawPayloadHash: normalized.rawPayloadHash,
        contentHash: normalized.contentHash,
        cleanerVersion: normalized.cleanerVersion,
        currentVersion: 1,
        rightsSnapshotId: input.rightsSnapshotId,
        rightsStatus: rights.status,
        reviewStatus,
        lifecycleStatus,
        riskLevel,
        publishedAt: normalized.publishedAt,
        sourceUpdatedAt: normalized.sourceUpdatedAt,
        normalizedAt: now,
        document: normalized.bodyText
          ? {
              create: {
                bodyText: normalized.bodyText,
                originalCharCount: normalized.originalCharCount,
                normalizedCharCount: normalized.normalizedCharCount,
                language: normalized.language,
                safetyFlags: jsonValue(normalized.safetyFlags),
              },
            }
          : undefined,
        versions: {
          create: {
            version: 1,
            contentHash: normalized.contentHash,
            cleanerVersion: normalized.cleanerVersion,
            policyVersion: normalized.policyVersion,
            title: normalized.originalTitle,
            excerpt: normalized.excerpt,
            changedFields: jsonValue(['initial']),
            changeReason: 'initial_ingestion',
          },
        },
      },
      select: { id: true, currentVersion: true },
    });
    return {
      itemId: created.id,
      action: 'created',
      version: created.currentVersion,
    };
  }

  if (existing.contentHash === normalized.contentHash) {
    await tx.contentItem.update({
      where: { id: existing.id },
      data: {
        metrics: jsonValue(normalized.metrics),
        rawPayloadHash: normalized.rawPayloadHash,
        rightsSnapshotId: input.rightsSnapshotId,
        rightsStatus: rights.status,
        reviewStatus,
        lifecycleStatus,
        riskLevel,
        sourceUpdatedAt: normalized.sourceUpdatedAt,
        lastSeenAt: now,
      },
    });
    return {
      itemId: existing.id,
      action: 'unchanged',
      version: existing.currentVersion,
    };
  }

  const nextVersion = existing.currentVersion + 1;
  await tx.contentItem.update({
    where: { id: existing.id },
    data: {
      originalUrl: normalized.originalUrl,
      canonicalUrl: normalized.canonicalUrl,
      canonicalUrlHash: normalized.canonicalUrlHash,
      originalTitle: normalized.originalTitle,
      normalizedTitle: normalized.normalizedTitle,
      excerpt: normalized.excerpt,
      contentType: normalized.contentType,
      language: normalized.language,
      authors: jsonValue(normalized.authors),
      tags: jsonValue(normalized.tags),
      metrics: jsonValue(normalized.metrics),
      rawPayloadHash: normalized.rawPayloadHash,
      contentHash: normalized.contentHash,
      cleanerVersion: normalized.cleanerVersion,
      currentVersion: nextVersion,
      rightsSnapshotId: input.rightsSnapshotId,
      rightsStatus: rights.status,
      reviewStatus,
      lifecycleStatus,
      riskLevel,
      publishedAt: normalized.publishedAt,
      sourceUpdatedAt: normalized.sourceUpdatedAt,
      normalizedAt: now,
      lastSeenAt: now,
    },
  });

  if (normalized.bodyText) {
    await tx.contentDocument.upsert({
      where: { contentItemId: existing.id },
      create: {
        contentItemId: existing.id,
        bodyText: normalized.bodyText,
        originalCharCount: normalized.originalCharCount,
        normalizedCharCount: normalized.normalizedCharCount,
        language: normalized.language,
        safetyFlags: jsonValue(normalized.safetyFlags),
      },
      update: {
        bodyText: normalized.bodyText,
        sanitizedHtml: null,
        originalCharCount: normalized.originalCharCount,
        normalizedCharCount: normalized.normalizedCharCount,
        language: normalized.language,
        safetyFlags: jsonValue(normalized.safetyFlags),
      },
    });
  } else {
    await tx.contentDocument.deleteMany({
      where: { contentItemId: existing.id },
    });
  }

  await tx.contentVersion.create({
    data: {
      contentItemId: existing.id,
      version: nextVersion,
      contentHash: normalized.contentHash,
      cleanerVersion: normalized.cleanerVersion,
      policyVersion: normalized.policyVersion,
      title: normalized.originalTitle,
      excerpt: normalized.excerpt,
      changedFields: jsonValue([
        'title',
        'excerpt',
        'bodyText',
        'authors',
        'tags',
        'publishedAt',
      ]),
      changeReason: 'source_content_changed',
    },
  });

  return {
    itemId: existing.id,
    action: 'updated',
    version: nextVersion,
  };
}

/**
 * Persists a normalized record atomically. Same hashes only refresh metadata;
 * changed hashes create a new immutable version.
 */
export async function persistNormalizedContent(
  prisma: DatabaseClient,
  input: PersistNormalizedContentInput,
): Promise<PersistNormalizedContentResult> {
  try {
    return await prisma.$transaction(
      (tx) => persistInTransaction(tx, input),
    );
  } catch (error) {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError
      && error.code === 'P2002'
    ) {
      return prisma.$transaction(
        (tx) => persistInTransaction(tx, input),
      );
    }
    throw error;
  }
}

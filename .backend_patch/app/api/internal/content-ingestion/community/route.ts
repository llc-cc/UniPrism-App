import { NextRequest } from 'next/server';
import { ok } from '@/lib/api/response';
import { withApiHandler } from '@/lib/api/handler';
import { prisma } from '@/lib/db';
import { assertCrawlerAuthorization } from '@/lib/content-ingestion/crawlerRouteAuthorization';
import {
  communityIngestionPayloadSchema,
  ingestCommunityEvidence,
} from '@/lib/content-ingestion/communityIngestion';
import {
  enqueueCommunityEvidenceAnalysis,
  getCommunityEvidenceAnalysisQueue,
} from '@/lib/community-analysis/queue';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 300;

/** 仅接收服务器爬虫使用共享令牌提交的已发现公开社区候选内容。 */
export const POST = withApiHandler(async (request: NextRequest) => {
  assertCrawlerAuthorization(request.headers.get('authorization') ?? '');
  const payload = communityIngestionPayloadSchema.parse(await request.json());
  return ok(await ingestCommunityEvidence(
    prisma,
    payload,
    undefined,
    (contentItemId, cleanerVersion) => enqueueCommunityEvidenceAnalysis(
      getCommunityEvidenceAnalysisQueue(),
      contentItemId,
      cleanerVersion,
    ),
  ));
});

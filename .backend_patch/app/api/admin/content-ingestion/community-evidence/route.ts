import { NextRequest } from 'next/server';
import { ok } from '@/lib/api/response';
import { withApiHandler } from '@/lib/api/handler';
import { prisma } from '@/lib/db';
import { requireAdminSession } from '@/lib/security/admin';
import {
  communityEvidenceListQuerySchema,
  listCommunityEvidence,
} from '@/lib/adminCommunityEvidence';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** 只返回脱敏后的待审核证据，不包含平台账号身份和原始快照。 */
export const GET = withApiHandler(async (request: NextRequest) => {
  await requireAdminSession();
  const query = communityEvidenceListQuerySchema.parse(
    Object.fromEntries(request.nextUrl.searchParams),
  );
  return ok(await listCommunityEvidence(query, prisma));
});

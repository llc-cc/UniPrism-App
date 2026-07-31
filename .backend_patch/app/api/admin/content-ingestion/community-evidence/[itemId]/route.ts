import { NextRequest } from 'next/server';
import { ApiError, ok } from '@/lib/api/response';
import { withApiHandler } from '@/lib/api/handler';
import { prisma } from '@/lib/db';
import { requireAdminSession } from '@/lib/security/admin';
import { assertSafeMutationRequest } from '@/lib/security/origin';
import {
  CommunityReviewError,
  communityEvidenceReviewSchema,
  reviewCommunityEvidence,
} from '@/lib/adminCommunityEvidence';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** 所有审核操作都校验页面读取时的版本，冲突时要求管理员刷新。 */
export const PATCH = withApiHandler(async (request: NextRequest) => {
  assertSafeMutationRequest(request);
  const admin = await requireAdminSession();
  // 现有 withApiHandler 只传入 request/requestId，因此从已匹配的路由路径读取资源 ID。
  const itemId = decodeURIComponent(
    request.nextUrl.pathname.split('/').filter(Boolean).at(-1) ?? '',
  );
  if (!itemId) {
    throw new ApiError('VALIDATION_ERROR', '缺少待审核内容 ID。', 400);
  }
  const input = communityEvidenceReviewSchema.parse(await request.json());
  try {
    return ok(await reviewCommunityEvidence(
      itemId,
      input,
      admin.userId,
      prisma,
    ));
  } catch (error) {
    if (error instanceof CommunityReviewError) {
      throw new ApiError(error.code, error.message, error.status);
    }
    throw error;
  }
});

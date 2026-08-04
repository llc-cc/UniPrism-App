import { NextRequest } from 'next/server';
import { ok } from '@/lib/api/response';
import { validateJsonBody } from '@/lib/api/validate';
import { withApiHandler } from '@/lib/api/handler';
import {
  assertKnowledgeExtractionEnvironment,
  extractKnowledgeBatch,
  knowledgeExtractionInputSchema,
} from '@/lib/knowledge-extraction/extractKnowledge';
import { assertSafeMutationRequest } from '@/lib/security/origin';
import { assertRateLimit, getClientIp } from '@/lib/security/rateLimit';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * 原型阶段只提供候选知识，客户端确认后才写入本地知识森林。
 */
export const POST = withApiHandler(async (request: NextRequest) => {
  assertKnowledgeExtractionEnvironment(process.env.NODE_ENV);
  assertSafeMutationRequest(request);
  const input = await validateJsonBody(request, knowledgeExtractionInputSchema);
  await assertRateLimit({
    namespace: 'dev.knowledge.extract.ip',
    key: getClientIp(request.headers),
    limit: 8,
    windowMs: 60_000,
  });

  return ok(await extractKnowledgeBatch(input));
});

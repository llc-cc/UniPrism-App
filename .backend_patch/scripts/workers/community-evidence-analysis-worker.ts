import { loadEnvConfig } from '@next/env';
import { Worker } from 'bullmq';
import { callDeepSeekJson } from '@/lib/ai/deepseek';
import { prisma } from '@/lib/db';
import { getBullMqConnectionOptions, pingRedis } from '@/lib/redis';
import { analyzeCommunityEvidence } from '@/lib/community-analysis/analyzer';
import {
  COMMUNITY_EVIDENCE_ANALYSIS_QUEUE_NAME,
} from '@/lib/community-analysis/queue';
import type {
  CommunityEvidenceAnalysisJobData,
} from '@/lib/community-analysis/contracts';

loadEnvConfig(process.cwd());

async function processJob(data: CommunityEvidenceAnalysisJobData) {
  const item = await prisma.contentItem.findUnique({
    where: { id: data.contentItemId },
    select: {
      cleanerVersion: true,
      document: { select: { bodyText: true } },
      communityEvidenceAnalysis: {
        select: {
          institutionCode: true,
          institutionName: true,
          platform: true,
          dimension: true,
        },
      },
    },
  });
  if (
    !item
    || !item.document
    || !item.communityEvidenceAnalysis
    || item.cleanerVersion !== data.cleanerVersion
  ) {
    throw new Error('COMMUNITY_EVIDENCE_NOT_READY');
  }

  await prisma.communityEvidenceAnalysis.update({
    where: { contentItemId: data.contentItemId },
    data: { analysisStatus: 'ai_processing' },
  });
  try {
    const analysis = await analyzeCommunityEvidence({
      contentItemId: data.contentItemId,
      institutionCode: 'peking-university',
      institutionName: '北京大学',
      platform: item.communityEvidenceAnalysis.platform as 'zhihu' | 'tieba',
      suggestedDimension:
        item.communityEvidenceAnalysis.dimension as
          | 'school'
          | 'major'
          | 'course'
          | 'employment'
          | 'dormitory'
          | 'cafeteria'
          | 'student_club',
      sanitizedText: item.document.bodyText,
    }, callDeepSeekJson);
    // Worker 只更新分析字段，绝不把待审核内容改成已通过。
    await prisma.communityEvidenceAnalysis.update({
      where: { contentItemId: data.contentItemId },
      data: {
        majorName: analysis.majorName,
        dimension: analysis.dimension,
        credibilityScore: analysis.credibility,
        sentiment: analysis.sentiment,
        claims: [{ text: analysis.claim, informationValue: analysis.informationValue }],
        analysisStatus: 'ai_completed',
        model: analysis.model,
        promptVersion: analysis.promptVersion,
      },
    });
  } catch (error) {
    await prisma.communityEvidenceAnalysis.update({
      where: { contentItemId: data.contentItemId },
      data: { analysisStatus: 'ai_failed' },
    });
    throw error;
  }
}

async function main() {
  if (await pingRedis() !== true) {
    console.error('Community evidence worker: Redis is unavailable.');
    process.exit(1);
  }
  const worker = new Worker<CommunityEvidenceAnalysisJobData>(
    COMMUNITY_EVIDENCE_ANALYSIS_QUEUE_NAME,
    async (job) => processJob(job.data),
    {
      connection: getBullMqConnectionOptions(),
      concurrency: 2,
    },
  );
  worker.on('completed', (job) => {
    console.log(`Community evidence analyzed: item=${job.data.contentItemId}`);
  });
  worker.on('failed', (job, error) => {
    console.error(
      `Community evidence analysis failed: item=${job?.data.contentItemId ?? 'unknown'} code=${error.name}`,
    );
  });
}

void main();

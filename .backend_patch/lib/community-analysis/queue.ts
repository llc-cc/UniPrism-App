import { Queue } from 'bullmq';
import { getBullMqConnectionOptions } from '@/lib/redis';
import type { CommunityEvidenceAnalysisJobData } from './contracts';

export const COMMUNITY_EVIDENCE_ANALYSIS_QUEUE_NAME =
  'community-evidence-analysis';
export const COMMUNITY_EVIDENCE_ANALYSIS_JOB_NAME =
  'community-evidence-analysis';

type QueueLike = {
  add: (
    name: typeof COMMUNITY_EVIDENCE_ANALYSIS_JOB_NAME,
    data: CommunityEvidenceAnalysisJobData,
    options: {
      jobId: string;
      attempts: number;
      backoff: { type: 'exponential'; delay: number };
      removeOnComplete: { age: number; count: number };
      removeOnFail: { age: number; count: number };
    },
  ) => Promise<unknown>;
};

declare global {
  // eslint-disable-next-line no-var
  var __uniprismCommunityEvidenceQueue: QueueLike | undefined;
}

export function getCommunityEvidenceAnalysisQueue(): QueueLike {
  if (!globalThis.__uniprismCommunityEvidenceQueue) {
    globalThis.__uniprismCommunityEvidenceQueue =
      new Queue<CommunityEvidenceAnalysisJobData>(
        COMMUNITY_EVIDENCE_ANALYSIS_QUEUE_NAME,
        { connection: getBullMqConnectionOptions() },
      ) as unknown as QueueLike;
  }
  return globalThis.__uniprismCommunityEvidenceQueue;
}

/** 相同内容版本只生成一个任务，避免重复采集造成重复 AI 消耗。 */
export async function enqueueCommunityEvidenceAnalysis(
  queue: QueueLike,
  contentItemId: string,
  cleanerVersion: string,
) {
  return queue.add(
    COMMUNITY_EVIDENCE_ANALYSIS_JOB_NAME,
    { contentItemId, cleanerVersion },
    {
      jobId: `${contentItemId}:${cleanerVersion}`,
      attempts: 3,
      backoff: { type: 'exponential', delay: 5_000 },
      removeOnComplete: { age: 24 * 60 * 60, count: 5_000 },
      removeOnFail: { age: 7 * 24 * 60 * 60, count: 5_000 },
    },
  );
}

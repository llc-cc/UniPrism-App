import { describe, expect, it, vi } from 'vitest';
import {
  COMMUNITY_EVIDENCE_ANALYSIS_JOB_NAME,
  enqueueCommunityEvidenceAnalysis,
} from '@/lib/community-analysis/queue';

describe('community evidence analysis queue', () => {
  it('uses content and cleaner version as the idempotent job id', async () => {
    const queue = { add: vi.fn().mockResolvedValue({ id: 'job-1' }) };

    await enqueueCommunityEvidenceAnalysis(
      queue,
      'content-item-1',
      'community-cleaner-v1',
    );

    expect(queue.add).toHaveBeenCalledWith(
      COMMUNITY_EVIDENCE_ANALYSIS_JOB_NAME,
      {
        contentItemId: 'content-item-1',
        cleanerVersion: 'community-cleaner-v1',
      },
      expect.objectContaining({
        jobId: 'content-item-1:community-cleaner-v1',
      }),
    );
  });
});

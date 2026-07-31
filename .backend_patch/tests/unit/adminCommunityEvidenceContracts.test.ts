import { describe, expect, it } from 'vitest';
import {
  communityEvidenceListQuerySchema,
  communityEvidenceReviewSchema,
} from '@/lib/adminCommunityEvidence';

describe('admin community evidence contracts', () => {
  it('caps the review page at twenty records', () => {
    expect(communityEvidenceListQuerySchema.parse({}).pageSize).toBe(20);
    expect(() => communityEvidenceListQuerySchema.parse({ pageSize: '21' }))
      .toThrow();
  });

  it('allows only explicit review actions', () => {
    expect(communityEvidenceReviewSchema.parse({
      action: 'approve',
      expectedUpdatedAt: '2026-07-31T01:00:00.000Z',
    }).action).toBe('approve');
    expect(() => communityEvidenceReviewSchema.parse({
      action: 'publish',
      expectedUpdatedAt: '2026-07-31T01:00:00.000Z',
    })).toThrow();
  });
});

export const COMMUNITY_PLATFORMS = ['zhihu', 'tieba'] as const;

export type CommunityPlatform = (typeof COMMUNITY_PLATFORMS)[number];

export type CommunityEvidenceInput = {
  title: string;
  text: string;
  platform: CommunityPlatform;
};

export type CommunityCleaningDecision = 'rejected' | 'review_required';

export type CommunityCleaningResult = {
  decision: CommunityCleaningDecision;
  sanitizedText: string;
  qualityScore: number;
  spamSignals: string[];
  privacyFlags: string[];
  contentHash: string;
  similarityHash: string;
};

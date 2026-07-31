import { z } from 'zod';

export const COMMUNITY_ANALYSIS_DIMENSIONS = [
  'school',
  'major',
  'course',
  'employment',
  'dormitory',
  'cafeteria',
  'student_club',
] as const;

export const communityEvidenceAnalysisSchema = z.object({
  institutionCode: z.literal('peking-university'),
  majorName: z.string().trim().min(1).max(160).nullable(),
  dimension: z.enum(COMMUNITY_ANALYSIS_DIMENSIONS),
  claim: z.string().trim().min(4).max(500),
  sentiment: z.record(
    z.string().max(40),
    z.enum(['positive', 'negative', 'neutral', 'mixed']),
  ).superRefine((value, context) => {
    const allowed = new Set<string>(COMMUNITY_ANALYSIS_DIMENSIONS);
    for (const key of Object.keys(value)) {
      if (!allowed.has(key)) {
        context.addIssue({
          code: 'custom',
          message: `Unsupported sentiment dimension: ${key}`,
        });
      }
    }
  }),
  informationValue: z.number().int().min(0).max(10),
  credibility: z.number().min(0).max(10),
  riskReasons: z.array(z.string().trim().min(1).max(120)).max(10),
  requiresHumanReview: z.literal(true),
}).strict();

export type CommunityEvidenceAnalysisResult = z.infer<
  typeof communityEvidenceAnalysisSchema
>;

export type CommunityEvidenceAnalysisInput = {
  contentItemId: string;
  institutionCode: 'peking-university';
  institutionName: '北京大学';
  platform: 'zhihu' | 'tieba';
  suggestedDimension: typeof COMMUNITY_ANALYSIS_DIMENSIONS[number];
  sanitizedText: string;
};

export type CommunityEvidenceAnalysisJobData = {
  contentItemId: string;
  cleanerVersion: string;
};

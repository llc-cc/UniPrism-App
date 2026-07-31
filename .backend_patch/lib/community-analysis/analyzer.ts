import {
  communityEvidenceAnalysisSchema,
  type CommunityEvidenceAnalysisInput,
  type CommunityEvidenceAnalysisResult,
} from './contracts';

type AiResult = {
  content: string;
  model: string;
  latencyMs: number;
  usage?: Record<string, unknown>;
};

type AiCall = (options: {
  modelEnvKey: string;
  fallbackModel: string;
  messages: Array<{
    role: 'system' | 'user';
    content: string;
  }>;
  temperature: number;
  timeoutMs: number;
  maxTokens: number;
  thinking: 'disabled';
}) => Promise<AiResult>;

/**
 * AI 只产生结构化辅助判断，不返回审核状态，最终是否可用必须由管理员决定。
 */
export async function analyzeCommunityEvidence(
  input: CommunityEvidenceAnalysisInput,
  aiCall: AiCall,
): Promise<CommunityEvidenceAnalysisResult & {
  model: string;
  promptVersion: 'community-evidence-v1';
}> {
  const result = await aiCall({
    modelEnvKey: 'DEEPSEEK_COMMUNITY_ANALYSIS_MODEL',
    fallbackModel:
      process.env.DEEPSEEK_DIALOGUE_MODEL
      || process.env.DEEPSEEK_REPORT_MODEL
      || 'deepseek-v4-flash',
    messages: [
      {
        role: 'system',
        content: [
          '你负责分析已脱敏的高校公开社区证据。',
          '只输出一个 JSON 对象，不得输出 Markdown。',
          '不得推断作者身份；不得把单条内容当作学校整体结论。',
          'dimension 只能是 school、major、course、employment、dormitory、cafeteria、student_club。',
          'informationValue 与 credibility 范围为 0 到 10。',
          'requiresHumanReview 必须为 true。',
        ].join('\n'),
      },
      {
        role: 'user',
        content: JSON.stringify({
          institutionCode: input.institutionCode,
          institutionName: input.institutionName,
          platform: input.platform,
          suggestedDimension: input.suggestedDimension,
          evidence: input.sanitizedText,
        }),
      },
    ],
    temperature: 0,
    timeoutMs: 12_000,
    maxTokens: 500,
    thinking: 'disabled',
  });

  const trimmed = result.content.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    throw new Error('Community analysis must be a strict JSON object.');
  }
  const parsed = communityEvidenceAnalysisSchema.parse(JSON.parse(trimmed));
  return {
    ...parsed,
    model: result.model,
    promptVersion: 'community-evidence-v1',
  };
}

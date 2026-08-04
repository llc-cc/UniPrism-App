import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import {
  callDeepSeekJson,
  type DeepSeekJsonResult,
} from '@/lib/ai/deepseek';

const treeSummarySchema = z.object({
  id: z.string().trim().min(1).max(80),
  title: z.string().trim().min(1).max(80),
}).strict();

export const knowledgeExtractionInputSchema = z.object({
  conversationId: z.string().trim().min(1).max(120),
  messageId: z.string().trim().min(1).max(120),
  question: z.string().trim().min(2).max(500),
  answer: z.string().trim().min(20).max(6_000),
  availableTrees: z.array(treeSummarySchema).max(20).default([]),
  clientTraceId: z.string().trim().min(1).max(120),
}).strict();

const candidateSchema = z.object({
  candidateId: z.string().trim().min(1).max(80),
  parentCandidateId: z.string().trim().min(1).max(80).nullable(),
  type: z.enum([
    'topic',
    'concept',
    'insight',
    'method',
    'action',
    'resource',
  ]),
  title: z.string().trim().min(1).max(80),
  summary: z.string().trim().min(1).max(240),
  confidence: z.number().min(0).max(1),
});

const relatedEdgeSchema = z.object({
  fromCandidateId: z.string().trim().min(1).max(80),
  toCandidateId: z.string().trim().min(1).max(80),
  relation: z.string().trim().min(1).max(40),
});

const modelBatchSchema = z.object({
  suggestedTree: z.object({
    mode: z.enum(['existing', 'new']),
    treeId: z.string().trim().min(1).max(80).nullable().default(null),
    title: z.string().trim().min(1).max(80),
  }),
  nodes: z.array(candidateSchema).max(20),
  relatedEdges: z.array(relatedEdgeSchema).max(30).default([]),
});

export type KnowledgeExtractionInput = z.infer<
  typeof knowledgeExtractionInputSchema
>;

export type KnowledgeCandidate = z.infer<typeof candidateSchema> & {
  selected: true;
};

export type KnowledgeExtractionBatch = {
  batchId: string;
  conversationId: string;
  messageId: string;
  question: string;
  answerExcerpt: string;
  suggestedTree: z.infer<typeof modelBatchSchema>['suggestedTree'];
  nodes: KnowledgeCandidate[];
  relatedEdges: z.infer<typeof relatedEdgeSchema>[];
  traceId: string;
  model: string;
  latencyMs: number;
};

type KnowledgeModelResult = Pick<
  DeepSeekJsonResult,
  'content' | 'model' | 'latencyMs'
>;

export type KnowledgeModelCaller = (
  options: Parameters<typeof callDeepSeekJson>[0],
) => Promise<KnowledgeModelResult>;

export class KnowledgeExtractionError extends Error {
  constructor(
    readonly code: 'NO_KNOWLEDGE_CANDIDATES' | 'INVALID_MODEL_RESPONSE',
    message: string,
  ) {
    super(message);
    this.name = 'KnowledgeExtractionError';
  }
}

function extractionMessages(input: KnowledgeExtractionInput) {
  return [
    {
      role: 'system' as const,
      content: [
        '你负责把教育、专业、学习或职业探索回答提炼为个人知识树候选。',
        '只输出 JSON，不要输出 Markdown，也不要生成 URL。',
        '节点类型只能是 topic、concept、insight、method、action、resource。',
        '最多 12 个节点；每个节点只设置一个主要父节点。',
        '不确定或缺少依据的内容不要提炼成确定事实。',
        '输出结构：',
        '{"suggestedTree":{"mode":"existing|new","treeId":"已有树ID或null","title":"主题树名称"},"nodes":[{"candidateId":"稳定批内ID","parentCandidateId":null,"type":"concept","title":"标题","summary":"摘要","confidence":0.8}],"relatedEdges":[]}',
      ].join('\n'),
    },
    {
      role: 'user' as const,
      content: JSON.stringify({
        question: input.question,
        answer: input.answer,
        availableTrees: input.availableTrees,
      }),
    },
  ];
}

function parseModelBatch(content: string) {
  try {
    const decoded = JSON.parse(
      content.trim()
        .replace(/^```(?:json)?\s*/i, '')
        .replace(/\s*```$/i, ''),
    );
    return modelBatchSchema.parse(decoded);
  } catch {
    throw new KnowledgeExtractionError(
      'INVALID_MODEL_RESPONSE',
      'AI 返回的知识结构无法识别。',
    );
  }
}

function normalizedTitle(title: string) {
  return title.replace(/\s+/gu, '').toLocaleLowerCase();
}

function normalizedCandidates(nodes: z.infer<typeof candidateSchema>[]) {
  const seenIds = new Set<string>();
  const seenTitles = new Set<string>();
  const kept = nodes.filter((node) => {
    const titleKey = normalizedTitle(node.title);
    if (seenIds.has(node.candidateId) || seenTitles.has(titleKey)) {
      return false;
    }
    seenIds.add(node.candidateId);
    seenTitles.add(titleKey);
    return true;
  }).slice(0, 12);
  const keptIds = new Set(kept.map((node) => node.candidateId));

  return kept.map((node) => ({
    ...node,
    parentCandidateId:
      node.parentCandidateId !== node.candidateId
      && node.parentCandidateId != null
      && keptIds.has(node.parentCandidateId)
        ? node.parentCandidateId
        : null,
    selected: true as const,
  }));
}

/**
 * 将 DeepSeek 的不可信 JSON 转换为有界候选批次；只有用户后续确认才会进入知识树。
 */
export async function extractKnowledgeBatch(
  input: KnowledgeExtractionInput,
  caller: KnowledgeModelCaller = callDeepSeekJson,
): Promise<KnowledgeExtractionBatch> {
  const safeInput = knowledgeExtractionInputSchema.parse(input);
  const result = await caller({
    modelEnvKey: 'DEEPSEEK_KNOWLEDGE_EXTRACTION_MODEL',
    fallbackModel:
      process.env.DEEPSEEK_DIALOGUE_MODEL
      || process.env.DEEPSEEK_REPORT_MODEL
      || 'deepseek-v4-flash',
    messages: extractionMessages(safeInput),
    temperature: 0.1,
    timeoutMs: 20_000,
    maxTokens: 1_600,
    thinking: 'disabled',
  });
  const parsed = parseModelBatch(result.content);
  const nodes = normalizedCandidates(parsed.nodes);
  if (nodes.length === 0) {
    throw new KnowledgeExtractionError(
      'NO_KNOWLEDGE_CANDIDATES',
      '这次回答暂未提炼出可保存的知识节点。',
    );
  }
  const retainedIds = new Set(nodes.map((node) => node.candidateId));
  const relatedEdges = parsed.relatedEdges.filter((edge) => (
    edge.fromCandidateId !== edge.toCandidateId
    && retainedIds.has(edge.fromCandidateId)
    && retainedIds.has(edge.toCandidateId)
  ));

  return {
    batchId: `knowledge-${randomUUID()}`,
    conversationId: safeInput.conversationId,
    messageId: safeInput.messageId,
    question: safeInput.question,
    answerExcerpt: safeInput.answer.slice(0, 500),
    suggestedTree: parsed.suggestedTree,
    nodes,
    relatedEdges,
    traceId: safeInput.clientTraceId,
    model: result.model,
    latencyMs: result.latencyMs,
  };
}

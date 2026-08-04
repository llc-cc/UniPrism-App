import { describe, expect, it } from 'vitest';
import {
  assertKnowledgeExtractionEnvironment,
  extractKnowledgeBatch,
  KnowledgeExtractionError,
  knowledgeExtractionInputSchema,
  type KnowledgeModelCaller,
} from '@/lib/knowledge-extraction/extractKnowledge';

const validInput = {
  conversationId: 'conv-1',
  messageId: 'msg-1',
  question: '人工智能专业学什么？',
  answer: '人工智能专业包括机器学习、智能系统和工程实践。',
  availableTrees: [{ id: 'tree-ai', title: '人工智能' }],
  clientTraceId: 'trace-1',
};

function callerReturning(payload: unknown): KnowledgeModelCaller {
  return async () => ({
    content: JSON.stringify(payload),
    model: 'deepseek-test',
    latencyMs: 12,
  });
}

describe('knowledge extraction', () => {
  it('rejects the development extraction endpoint in production', () => {
    expect(() => assertKnowledgeExtractionEnvironment('production'))
      .toThrow(/仅用于开发联调/);
  });

  it('rejects oversized answers and excessive tree summaries', () => {
    expect(() => knowledgeExtractionInputSchema.parse({
      ...validInput,
      answer: 'a'.repeat(6_001),
    })).toThrow();

    expect(() => knowledgeExtractionInputSchema.parse({
      ...validInput,
      availableTrees: Array.from({ length: 21 }, (_, index) => ({
        id: `tree-${index}`,
        title: `Tree ${index}`,
      })),
    })).toThrow();
  });

  it('normalizes candidates and clears a missing parent', async () => {
    const result = await extractKnowledgeBatch(
      validInput,
      callerReturning({
        suggestedTree: {
          mode: 'existing',
          treeId: 'tree-ai',
          title: '人工智能',
        },
        nodes: [
          {
            candidateId: 'root',
            parentCandidateId: null,
            type: 'topic',
            title: '人工智能',
            summary: '主题摘要',
            confidence: 0.91,
          },
          {
            candidateId: 'child',
            parentCandidateId: 'missing',
            type: 'concept',
            title: '机器学习',
            summary: '从数据学习规律',
            confidence: 0.83,
          },
        ],
        relatedEdges: [],
      }),
    );

    expect(result.nodes).toHaveLength(2);
    expect(result.nodes[0]).toMatchObject({
      candidateId: 'root',
      selected: true,
    });
    expect(result.nodes[1].parentCandidateId).toBeNull();
    expect(result.model).toBe('deepseek-test');
  });

  it('deduplicates equivalent titles and never exposes model-provided URLs', async () => {
    const result = await extractKnowledgeBatch(
      validInput,
      callerReturning({
        suggestedTree: { mode: 'new', title: '数学' },
        nodes: [
          {
            candidateId: 'linear-algebra-1',
            parentCandidateId: null,
            type: 'concept',
            title: '线性代数',
            summary: '研究向量、矩阵与线性变换。',
            confidence: 0.93,
            sourceUrl: 'https://untrusted.example/model-invented',
          },
          {
            candidateId: 'linear-algebra-2',
            parentCandidateId: null,
            type: 'concept',
            title: '线性 代数',
            summary: '重复的线性代数节点。',
            confidence: 0.78,
          },
        ],
        relatedEdges: [],
      }),
    );

    expect(result.nodes).toHaveLength(1);
    expect(result.nodes[0]).not.toHaveProperty('sourceUrl');
  });

  it('rejects a batch with no usable knowledge candidates', async () => {
    const promise = extractKnowledgeBatch(
      validInput,
      callerReturning({
        suggestedTree: { mode: 'new', title: '人工智能' },
        nodes: [],
        relatedEdges: [],
      }),
    );

    await expect(promise).rejects.toMatchObject<KnowledgeExtractionError>({
      code: 'NO_KNOWLEDGE_CANDIDATES',
    });
  });

  it('keeps only relations between distinct retained candidates', async () => {
    const result = await extractKnowledgeBatch(
      validInput,
      callerReturning({
        suggestedTree: { mode: 'new', title: '人工智能' },
        nodes: [
          {
            candidateId: 'ai',
            parentCandidateId: null,
            type: 'topic',
            title: '人工智能',
            summary: '人工智能的主题概览。',
            confidence: 0.91,
          },
          {
            candidateId: 'ml',
            parentCandidateId: 'ai',
            type: 'concept',
            title: '机器学习',
            summary: '从数据中学习规律。',
            confidence: 0.88,
          },
        ],
        relatedEdges: [
          { fromCandidateId: 'ai', toCandidateId: 'ml', relation: '包含' },
          { fromCandidateId: 'ai', toCandidateId: 'missing', relation: '相关' },
          { fromCandidateId: 'ml', toCandidateId: 'ml', relation: '相关' },
        ],
      }),
    );

    expect(result.relatedEdges).toEqual([
      { fromCandidateId: 'ai', toCandidateId: 'ml', relation: '包含' },
    ]);
  });
});

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('community evidence Prisma schema', () => {
  const schema = readFileSync(
    'prisma/schema.prisma',
    'utf8',
  );

  it('stores reviewable analysis separately from the evidence body', () => {
    expect(schema).toContain('model CommunityEvidenceAnalysis');
    expect(schema).toContain('contentItemId');
    expect(schema).toContain('institutionCode');
    expect(schema).toContain('dimension');
    expect(schema).toContain('qualityScore');
    expect(schema).toContain('similarityHash');
    expect(schema).toContain('@@map("community_evidence_analyses")');
  });

  it('allows generic ingestion batches to expose stage counts', () => {
    expect(schema).toMatch(
      /model ContentIngestionBatch[\s\S]*stageMetrics\s+Json\?/,
    );
  });
});

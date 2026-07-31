import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('community evidence admin page', () => {
  const dashboard = readFileSync(
    '.backend_patch/app/admin/content-ingestion/AdminContentIngestionDashboardClient.tsx',
    'utf8',
  );
  const reviewPage = readFileSync(
    '.backend_patch/app/admin/content-ingestion/CommunityEvidenceReviewClient.tsx',
    'utf8',
  );

  it('adds only a content-review entry under the content monitor', () => {
    expect(dashboard).toContain('内容审核');
    expect(dashboard).toContain('/admin/content-ingestion/community-evidence');
    expect(dashboard).not.toContain('/admin/invites');
  });

  it('defaults to pending evidence and supports all pilot filters', () => {
    expect(reviewPage).toContain("useState<ReviewStatus>('pending')");
    for (const dimension of [
      '学校整体',
      '专业',
      '课程',
      '就业',
      '宿舍',
      '食堂',
      '社团',
    ]) {
      expect(reviewPage).toContain(dimension);
    }
    expect(reviewPage).toContain('pageSize=20');
  });

  it('has safe source links and explicit review actions', () => {
    expect(reviewPage).toContain('rel="noreferrer"');
    expect(reviewPage).toContain('编辑后通过');
    expect(reviewPage).toContain('通过');
    expect(reviewPage).toContain('拒绝');
    expect(reviewPage).not.toMatch(/username|accountId|avatar|rawSnapshot/);
  });
});

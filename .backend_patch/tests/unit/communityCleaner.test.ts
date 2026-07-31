import { describe, expect, it } from 'vitest';
import { cleanCommunityEvidence } from '@/lib/content-ingestion/communityCleaner';

describe('cleanCommunityEvidence', () => {
  it('rejects meaningless short reactions before AI processing', () => {
    const result = cleanCommunityEvidence({
      text: '哈哈哈哈',
      title: '北大',
      platform: 'zhihu',
    });

    expect(result.decision).toBe('rejected');
    expect(result.spamSignals).toContain('low_information');
  });

  it('redacts contact details and keeps the record in human review', () => {
    const result = cleanCommunityEvidence({
      text: '课程体验很充实，想交流可以加微信 abc_123456，电话 13800138000。',
      title: '北京大学课程体验',
      platform: 'tieba',
    });

    expect(result.sanitizedText).not.toContain('abc_123456');
    expect(result.sanitizedText).not.toContain('13800138000');
    expect(result.privacyFlags).toContain('wechat_id');
    expect(result.privacyFlags).toContain('phone');
    expect(result.decision).toBe('review_required');
  });

  it('does not reject a normal discussion merely because it mentions WeChat', () => {
    const result = cleanCommunityEvidence({
      text: '学校微信公众号会发布选课时间，建议开学后关注教务通知。',
      title: '北京大学选课',
      platform: 'zhihu',
    });

    expect(result.decision).toBe('review_required');
    expect(result.spamSignals).not.toContain('solicitation');
  });

  it('rejects content with multiple advertising and solicitation signals', () => {
    const result = cleanCommunityEvidence({
      text: '留学咨询限时优惠，扫码报名，加微信 study_888 领取代理价格。',
      title: '北大经验',
      platform: 'tieba',
    });

    expect(result.decision).toBe('rejected');
    expect(result.spamSignals).toContain('solicitation');
    expect(result.spamSignals).toContain('promotion');
  });

  it('keeps detailed first-person experience for review with a useful score', () => {
    const result = cleanCommunityEvidence({
      text: '我在北京大学计算机专业读了四年。大一课程包括高等数学和程序设计，作业量较大，但实验室和就业资源都比较丰富。',
      title: '北京大学计算机专业学习体验',
      platform: 'zhihu',
    });

    expect(result.decision).toBe('review_required');
    expect(result.qualityScore).toBeGreaterThanOrEqual(60);
    expect(result.contentHash).toMatch(/^[a-f0-9]{64}$/);
    expect(result.similarityHash).toMatch(/^[a-f0-9]{16}$/);
  });
});

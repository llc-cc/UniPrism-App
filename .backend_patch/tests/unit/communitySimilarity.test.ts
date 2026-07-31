import { describe, expect, it } from 'vitest';
import {
  computeSimilarityHash,
  isNearDuplicate,
} from '@/lib/content-ingestion/communitySimilarity';

describe('community similarity', () => {
  it('returns a deterministic 64-bit hexadecimal SimHash', () => {
    const left = computeSimilarityHash('北京大学计算机专业课程压力较大');
    const right = computeSimilarityHash('北京大学计算机专业课程压力较大');

    expect(left).toBe(right);
    expect(left).toMatch(/^[a-f0-9]{16}$/);
  });

  it('recognizes small wording changes as near duplicates', () => {
    expect(isNearDuplicate(
      '北大计算机课程压力很大，但科研资源丰富',
      '北京大学计算机专业课程压力较大，但是科研资源很丰富',
    )).toBe(true);
  });

  it('does not merge unrelated student experiences', () => {
    expect(isNearDuplicate(
      '北大计算机课程压力很大，但科研资源丰富',
      '学校食堂早餐种类很多，宿舍离教学楼比较远',
    )).toBe(false);
  });
});

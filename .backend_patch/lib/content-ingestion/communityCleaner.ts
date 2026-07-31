import { createHash } from 'node:crypto';
import type {
  CommunityCleaningResult,
  CommunityEvidenceInput,
} from './communityContracts';
import { computeSimilarityHash } from './communitySimilarity';

const LOW_INFORMATION_PATTERNS = [
  /^哈+$/u,
  /^6+$/u,
  /^(牛逼|厉害|顶|路过|沙发)$/u,
];

const SOLICITATION_PATTERNS = [
  /加\s*(?:微信|vx|wechat|qq)/iu,
  /私信我|联系我|进群|扫码|领取/iu,
];

const PROMOTION_PATTERNS = [
  /限时|优惠|代理|报名|咨询|价格|留学中介/iu,
];

function normalizeVisibleText(value: string) {
  return value
    .normalize('NFKC')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function redactPrivateData(value: string) {
  const privacyFlags: string[] = [];
  let sanitizedText = value;

  const replacements: Array<{
    flag: string;
    pattern: RegExp;
  }> = [
    {
      flag: 'email',
      pattern: /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu,
    },
    {
      flag: 'phone',
      pattern: /(?<!\d)1[3-9]\d{9}(?!\d)/g,
    },
    {
      flag: 'wechat_id',
      pattern: /(?:加\s*)?(?:微信|vx|wechat)\s*(?:号|id)?\s*[:：]?\s*[a-z][-_a-z0-9]{5,19}/giu,
    },
    {
      flag: 'qq_id',
      pattern: /(?:加\s*)?qq\s*(?:号)?\s*[:：]?\s*[1-9]\d{4,11}/giu,
    },
  ];

  for (const replacement of replacements) {
    if (!replacement.pattern.test(sanitizedText)) continue;
    privacyFlags.push(replacement.flag);
    replacement.pattern.lastIndex = 0;
    sanitizedText = sanitizedText.replace(replacement.pattern, '[已脱敏]');
  }

  return {
    sanitizedText: normalizeVisibleText(sanitizedText),
    privacyFlags,
  };
}

function isLowInformation(value: string) {
  const comparable = value
    .replace(/\[已脱敏]/g, '')
    .replace(/[^\p{Script=Han}a-z0-9]/giu, '');
  if (comparable.length < 8) return true;
  return LOW_INFORMATION_PATTERNS.some((pattern) => pattern.test(comparable));
}

function calculateQualityScore(
  value: string,
  privacyFlags: string[],
  spamSignals: string[],
) {
  let score = 35;
  if (value.length >= 30) score += 20;
  if (value.length >= 60) score += 15;
  if (/课程|专业|就业|宿舍|食堂|社团|科研|资源|作业|教学/u.test(value)) score += 15;
  if (/我在|我读|本人|大一|大二|大三|大四|四年/u.test(value)) score += 10;
  score -= privacyFlags.length * 10;
  score -= spamSignals.length * 20;
  return Math.max(0, Math.min(100, score));
}

/**
 * 首批社区内容无论分数高低都不能自动通过；规则层只负责拒绝明确垃圾或送人工审核。
 */
export function cleanCommunityEvidence(
  input: CommunityEvidenceInput,
): CommunityCleaningResult {
  const normalizedText = normalizeVisibleText(input.text);
  const { sanitizedText, privacyFlags } = redactPrivateData(normalizedText);
  const spamSignals: string[] = [];

  const hasSolicitation = SOLICITATION_PATTERNS.some((pattern) => pattern.test(normalizedText));
  const hasPromotion = PROMOTION_PATTERNS.some((pattern) => pattern.test(normalizedText));
  if (hasSolicitation) spamSignals.push('solicitation');
  if (hasPromotion) spamSignals.push('promotion');
  if (isLowInformation(sanitizedText)) spamSignals.push('low_information');

  const shouldReject = spamSignals.includes('low_information')
    || (hasSolicitation && hasPromotion);
  const qualityScore = calculateQualityScore(
    sanitizedText,
    privacyFlags,
    spamSignals,
  );

  return {
    decision: shouldReject ? 'rejected' : 'review_required',
    sanitizedText,
    qualityScore,
    spamSignals,
    privacyFlags,
    contentHash: createHash('sha256').update(sanitizedText).digest('hex'),
    similarityHash: computeSimilarityHash(sanitizedText),
  };
}

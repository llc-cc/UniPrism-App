import type { ContentRightsPolicy } from './contracts';
import type { CommunityPlatform } from './communityContracts';

export type CommunitySourceDefinition = {
  platform: CommunityPlatform;
  code: string;
  displayName: string;
  sourceUrl: string;
  allowedHosts: string[];
  policy: ContentRightsPolicy;
};

const POLICY_VERSION = 'community-public-review-v1';

function policy(
  provider: string,
  allowedHosts: string[],
): ContentRightsPolicy {
  return {
    provider,
    policyVersion: POLICY_VERSION,
    allowedHosts,
    allowStoreMetadata: true,
    allowStoreExcerpt: true,
    allowStoreBody: true,
    allowStoreRawSnapshot: false,
    allowAiProcess: true,
    allowRecommend: false,
    allowPush: false,
    maxExcerptChars: 800,
    maxBodyChars: 20_000,
  };
}

const definitions: Record<CommunityPlatform, CommunitySourceDefinition> = {
  zhihu: {
    platform: 'zhihu',
    code: 'zhihu-peking-university-public',
    displayName: '知乎·北京大学公开讨论',
    sourceUrl: 'https://www.zhihu.com/',
    allowedHosts: ['zhihu.com', 'www.zhihu.com', 'zhuanlan.zhihu.com'],
    policy: policy(
      'zhihu-peking-university-public',
      ['zhihu.com', 'www.zhihu.com', 'zhuanlan.zhihu.com'],
    ),
  },
  tieba: {
    platform: 'tieba',
    code: 'tieba-peking-university-public',
    displayName: '百度贴吧·北京大学公开讨论',
    sourceUrl: 'https://tieba.baidu.com/',
    allowedHosts: ['tieba.baidu.com'],
    policy: policy(
      'tieba-peking-university-public',
      ['tieba.baidu.com'],
    ),
  },
};

export function getCommunitySource(platform: CommunityPlatform) {
  return definitions[platform];
}

export function isAllowedCommunityUrl(
  platform: CommunityPlatform,
  value: string,
) {
  try {
    const host = new URL(value).hostname.toLocaleLowerCase('en-US');
    return definitions[platform].allowedHosts.some(
      (allowed) => host === allowed || host.endsWith(`.${allowed}`),
    );
  } catch {
    return false;
  }
}

import { createHash } from 'node:crypto';

function normalizeForSimilarity(value: string) {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase('zh-CN')
    .replace(/北京大学/g, '北大')
    .replace(/计算机专业/g, '计算机')
    .replace(/但是|不过/g, '但')
    .replace(/比较|较为|很/g, '')
    .replace(/较大/g, '大')
    .replace(/[^\p{Script=Han}a-z0-9]+/gu, '');
}

function buildFeatures(value: string) {
  const normalized = normalizeForSimilarity(value);
  const features: string[] = [];
  for (let index = 0; index < normalized.length - 1; index += 1) {
    features.push(normalized.slice(index, index + 2));
  }
  return features.length > 0 ? features : [normalized || 'empty'];
}

/**
 * 使用稳定的 64 位 SimHash 生成近义聚类信号；它只辅助分组，不单独决定删除证据。
 */
export function computeSimilarityHash(value: string) {
  const vector = Array<number>(64).fill(0);
  for (const feature of buildFeatures(value)) {
    const digest = BigInt(`0x${createHash('sha256').update(feature).digest('hex').slice(0, 16)}`);
    for (let bit = 0; bit < 64; bit += 1) {
      vector[bit] += (digest & (1n << BigInt(bit))) === 0n ? -1 : 1;
    }
  }

  let hash = 0n;
  vector.forEach((weight, bit) => {
    if (weight >= 0) hash |= 1n << BigInt(bit);
  });
  return hash.toString(16).padStart(16, '0');
}

function hammingDistance(left: string, right: string) {
  let value = BigInt(`0x${left}`) ^ BigInt(`0x${right}`);
  let distance = 0;
  while (value > 0n) {
    distance += Number(value & 1n);
    value >>= 1n;
  }
  return distance;
}

function bigramJaccard(left: string, right: string) {
  const leftFeatures = new Set(buildFeatures(left));
  const rightFeatures = new Set(buildFeatures(right));
  const intersection = [...leftFeatures].filter((feature) => rightFeatures.has(feature)).length;
  const union = new Set([...leftFeatures, ...rightFeatures]).size;
  return union === 0 ? 0 : intersection / union;
}

export function isNearDuplicate(
  left: string,
  right: string,
  maxDistance = 18,
) {
  if (normalizeForSimilarity(left) === normalizeForSimilarity(right)) return true;
  const similarity = bigramJaccard(left, right);
  if (similarity >= 0.48) return true;
  return similarity >= 0.3
    && hammingDistance(
      computeSimilarityHash(left),
      computeSimilarityHash(right),
    ) <= maxDistance;
}

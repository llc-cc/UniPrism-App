import path from 'node:path';

const canonicalBackend = 'D:/ywkeji/Uniprism/UniPrism_New-main';
const canonicalContentSourceAliases = Object.fromEntries([
  'crossref',
  'esco',
  'onet',
  'hackerNews',
  'zhihu',
  'github',
  'openAlex',
  'arxiv',
  'pubmed',
  'stackExchange',
  'huggingFace',
  'zhihuHotList',
  'worldBank',
  'wikimedia',
  'wikidata',
  'gbif',
  'nasa',
  'metMuseum',
  'musicBrainz',
  'moeMajorCatalog',
].map((name) => [
  `@/lib/content-sources/${name}`,
  path.resolve(canonicalBackend, `lib/content-sources/${name}.ts`),
]));

export default {
  resolve: {
    alias: {
      ...canonicalContentSourceAliases,
      '@/lib/ai/deepseek': path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/lib/ai/deepseek.ts',
      ),
      '@/lib/api/response': path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/lib/api/response.ts',
      ),
      '@/lib/databaseResilience': path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/lib/databaseResilience.ts',
      ),
      '@/lib/db': path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/lib/db.ts',
      ),
      '@/lib/redis': path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/lib/redis.ts',
      ),
      '@': path.resolve(__dirname, '.backend_patch'),
      zod: path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/node_modules/zod',
      ),
      '@prisma/client': path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/node_modules/@prisma/client',
      ),
      bullmq: path.resolve(
        'D:/ywkeji/Uniprism/UniPrism_New-main/node_modules/bullmq',
      ),
    },
  },
  test: {
    environment: 'node',
    include: ['.backend_patch/tests/**/*.test.ts'],
  },
};

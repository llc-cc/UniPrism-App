import path from 'node:path';

export default {
  resolve: {
    alias: {
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

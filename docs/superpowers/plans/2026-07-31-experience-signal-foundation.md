# UniPrism B 类学校体验语料地基 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为北京大学建立知乎、贴吧低频体验语料的本地登录采集、合规清洗、人工审核、多来源聚合和 App 安全检索闭环。

**Architecture:** 本地 Python Agent 通过回环 CDP 连接用户已登录的专用 Chrome，只上传最小采集结果和运行状态；Next.js 后端负责来源治理、可选加密短期原文、脱敏清洗、AI 结构化、人工审核和聚合。App 只检索已经审核发布的 `ExperienceSignalAggregate`，并把它显示为“学生体验汇总”，不把单条评论或评论者身份当作来源结论。

**Tech Stack:** Python 3.11、Browser Use 0.12.x、Pydantic 2、Next.js 16、TypeScript 5、Prisma 5/MySQL、Vitest 4、BullMQ/Redis、Flutter/Dart。

## Global Constraints

- 首期实体固定为北京大学，不构建北京城市画像。
- 首期平台固定为知乎、贴吧。
- 首期维度固定为学校整体、专业资源、课程与学习强度、就业与升学、宿舍、食堂、社团与校园文化。
- 首次快照手动触发；社区定时器保持关闭，验收后才配置 3–6 个月刷新。
- 来源等级 `S1–S4` 与内容流 `fresh / experience` 分开保存；B 类体验不能覆盖 S1/S2 官方事实。
- 不绕过登录、验证码、403、付费墙或平台反自动化措施；阻断必须如实记录。
- CDP 只允许 `127.0.0.1`、`localhost` 或 `::1`，不得接受公网或局域网地址。
- Cookie、浏览器配置、账号密码和跨站身份信息不得上传 ECS。
- 原始文本只有来源政策允许且确有复核需要时才使用 AES-256-GCM 加密短期保存；到期删除必须可审计。
- 普通用户昵称、头像、主页、联系方式和跨平台身份标识不得进入长期数据。
- 首批清洗证据和聚合结果均需人工审核；未经审核内容不得被 App 检索。
- App 不展示“采集、清洗、同步、候选、任务”等内部状态，不逐条展示社区评论。
- 只修改内容采集监控中心和 App 内容回答链路，不修改邀请码、用户管理及其他管理页面。
- 新增业务规则、异步状态、安全与隐私分支使用简洁中文注释。
- 后端至少运行相关 Vitest；采集器至少运行相关 Pytest；Flutter 至少运行相关测试和静态分析。

---

## File Structure

### Backend and database

- `.backend_patch/prisma/schema.prisma`：生产 Prisma 主模型，增加来源治理、体验任务、原始样本、证据、聚合及关联表。
- `.backend_patch/prisma/content-ingestion-schema.prisma`：内容采集模型镜像，保持部署补丁可独立审阅。
- `.backend_patch/prisma/migrations/20260731_experience_signal_foundation/migration.sql`：只通过迁移创建表、索引、约束和枚举变更。
- `.backend_patch/lib/experience-signals/contracts.ts`：七维枚举、运行状态、审核状态和 API 数据契约的唯一来源。
- `.backend_patch/lib/experience-signals/sourceGovernance.ts`：来源等级、内容流、权利快照和访问范围门禁。
- `.backend_patch/lib/experience-signals/rawCrypto.ts`：原文 AES-256-GCM 加密、解密和密钥配置校验。
- `.backend_patch/lib/experience-signals/cleaner.ts`：格式、垃圾、隐私和安全基础过滤。
- `.backend_patch/lib/experience-signals/analyzer.ts`：调用 AI 生成严格结构化的体验证据。
- `.backend_patch/lib/experience-signals/aggregator.ts`：仅从已审核证据生成待审核聚合。
- `.backend_patch/lib/experience-signals/repository.ts`：体验任务、样本、证据和聚合的数据库写入边界。
- `.backend_patch/lib/experience-signals/search.ts`：只读取已审核发布、未过期的体验聚合。
- `.backend_patch/lib/experience-signals/retention.ts`：到期原文清除和审计。
- `.backend_patch/lib/adminExperienceSignals.ts`：管理端查询、来源政策审核、证据审核和聚合审核。
- `.backend_patch/lib/content-ingestion/communityIngestion.ts`：把现有社区试点入库切换为体验任务和样本入口。
- `.backend_patch/lib/community-analysis/*`：保留 BullMQ worker 外壳，改为调用新的体验分析服务。
- `.backend_patch/lib/content-library/storedAnswer.ts`：合并官方内容检索与体验聚合检索。
- `.backend_patch/lib/content-sources/sourceTypes.ts`：增加来源展示元数据，不改变已有外部链接来源。
- `.backend_patch/lib/content-sources/unifiedAnswer.ts`：在提示词和排序中区分官方事实与体验汇总。

### Admin

- `.backend_patch/app/admin/content-ingestion/community-evidence/page.tsx`：保留现有路由，页面改为“学校体验语料”。
- `.backend_patch/app/admin/content-ingestion/ExperienceSignalsClient.tsx`：运行、证据、聚合和来源治理四个标签页。
- `.backend_patch/app/api/admin/content-ingestion/experience-signals/route.ts`：管理端只读列表。
- `.backend_patch/app/api/admin/content-ingestion/experience-signals/[resourceId]/route.ts`：证据和聚合审核。
- `.backend_patch/app/api/admin/content-ingestion/experience-signals/recompute/route.ts`：管理员触发聚合重算。
- `.backend_patch/app/api/admin/content-ingestion/experience-sources/[sourceCode]/route.ts`：来源政策审核。
- `.backend_patch/app/api/internal/content-ingestion/community/route.ts`：接收本地 Agent 的批次、样本和最终运行状态。

### Local crawler

- `.crawler_scaffold/university-crawler/src/university_crawler/config.py`：增加 `COMMUNITY_AGENT_CDP_URL`。
- `.crawler_scaffold/university-crawler/src/university_crawler/community_browser.py`：回环 CDP 校验和浏览器生命周期策略。
- `.crawler_scaffold/university-crawler/src/university_crawler/community_agent.py`：连接现有 Chrome，断开时不关闭用户浏览器。
- `.crawler_scaffold/university-crawler/src/university_crawler/community_ingestion.py`：允许零样本运行报告并上传最终状态。
- `.crawler_scaffold/university-crawler/src/university_crawler/community_runner.py`：修正 blocked、partial、failed 顶层状态。
- `.crawler_scaffold/university-crawler/src/university_crawler/community_models.py`：运行报告和阻断原因契约。
- `tool/run_experience_snapshot.ps1`：Windows 本地预检并手动执行首次快照。

### Flutter

- `lib/unified_content_answer_test.dart`：解析体验聚合展示元数据，并对体验来源卡隐藏“复制原始链接”。
- `test/widget_test.dart`：验证体验聚合卡片、官方来源卡片和低置信度提示。

### Operations and tests

- `.backend_patch/scripts/cleanup-expired-experience-raw.ts`：执行可审计的短期原文清理。
- `.backend_patch/scripts/workers/community-evidence-analysis-worker.ts`：消费清洗后的体验分析任务。
- `docs/operations/experience-snapshot-runbook.md`：本地登录、来源审批、采集、审核、聚合和排障手册。
- `deploy/uniprism-community-evidence-pilot/*`：更新后端部署包；ECS 社区定时器继续保持关闭。

---

### Task 1: Add source governance and experience data schema

**Files:**
- Create: `.backend_patch/prisma/migrations/20260731_experience_signal_foundation/migration.sql`
- Create: `.backend_patch/tests/unit/experienceSignalSchema.test.ts`
- Modify: `.backend_patch/prisma/schema.prisma`
- Modify: `.backend_patch/prisma/content-ingestion-schema.prisma`

**Interfaces:**
- Consumes: existing `ContentSource`, `ContentRightsSnapshot`, `ContentIngestionTrigger`.
- Produces: Prisma models `ExperienceCollectionRun`, `ExperienceRawSample`, `ExperienceEvidence`, `ExperienceSignalAggregate`, `ExperienceAggregateEvidence`.

- [ ] **Step 1: Write the failing schema test**

```ts
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('experience signal schema', () => {
  const schema = readFileSync('prisma/schema.prisma', 'utf8');

  it('separates source authority from content flow', () => {
    expect(schema).toContain('enum ContentSourceTier');
    expect(schema).toContain('enum ContentFlowType');
    expect(schema).toMatch(/model ContentSource[\s\S]*sourceTier\s+ContentSourceTier\?/);
    expect(schema).toMatch(/model ContentSource[\s\S]*contentFlowType\s+ContentFlowType\?/);
  });

  it('stores temporary samples, reviewable evidence and published aggregates separately', () => {
    for (const model of [
      'ExperienceCollectionRun',
      'ExperienceRawSample',
      'ExperienceEvidence',
      'ExperienceSignalAggregate',
      'ExperienceAggregateEvidence',
    ]) {
      expect(schema).toContain(`model ${model}`);
    }
    expect(schema).toMatch(
      /model ExperienceRawSample[\s\S]*retentionUntil\s+DateTime/,
    );
    expect(schema).toMatch(
      /model ExperienceSignalAggregate[\s\S]*reviewStatus\s+ExperienceReviewStatus/,
    );
  });
});
```

- [ ] **Step 2: Run the schema test and confirm it fails**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceSignalSchema.test.ts
```

Expected: FAIL because the experience enums and models do not exist.

- [ ] **Step 3: Add the Prisma enums and models**

Add these enums and use the same definitions in both Prisma schema files:

```prisma
enum ContentSourceTier {
  S1
  S2
  S3
  S4
}

enum ContentFlowType {
  fresh
  experience
}

enum ContentAccessMethod {
  public_page
  authenticated_public_page
  official_api
  authorized_export
}

enum ExperienceRunStatus {
  queued
  running
  completed
  partial
  failed
  blocked
}

enum ExperienceRawStatus {
  pending
  cleaned
  rejected
  aggregated
  deleted
}

enum ExperienceAspect {
  school_overall
  major_resources
  course_and_workload
  career_and_employment
  dormitory
  canteen
  clubs_and_culture
}

enum ExperienceSentiment {
  positive
  neutral
  mixed
  negative
}

enum ExperienceQualityStatus {
  high_value
  usable
  low_context
  duplicate
  spam
  unsafe
}

enum ExperienceReviewStatus {
  pending
  approved
  rejected
}
```

Extend `ContentSource` with nullable governance fields so existing sources migrate safely:

```prisma
sourceTier           ContentSourceTier?
contentFlowType      ContentFlowType?
accessMethod         ContentAccessMethod?
allowedScopes        Json?
forbiddenScopes      Json?
robotsReviewedAt     DateTime?
termsReviewedAt      DateTime?
nextPolicyReviewAt   DateTime?
requestRatePerMinute Int?
retentionPolicyVersion String? @db.VarChar(80)
experienceRawSamples ExperienceRawSample[]
```

Add the new models:

```prisma
model ExperienceCollectionRun {
  id                String              @id @default(cuid())
  externalRunId     String              @db.VarChar(191)
  platformType      String              @db.VarChar(40)
  entityType        String              @db.VarChar(40)
  entityId          String              @db.VarChar(191)
  institutionCode   String              @db.VarChar(80)
  trigger           ContentIngestionTrigger
  discoveryMode     String              @db.VarChar(40)
  status            ExperienceRunStatus @default(queued)
  counters          Json?
  blockReasons      Json?
  startedAt         DateTime?
  completedAt       DateTime?
  createdAt         DateTime            @default(now())
  updatedAt         DateTime            @updatedAt

  rawSamples ExperienceRawSample[]

  @@unique([externalRunId, platformType])
  @@index([institutionCode, createdAt])
  @@index([status, createdAt])
  @@map("experience_collection_runs")
}

model ExperienceRawSample {
  id                    String              @id @default(cuid())
  runId                 String
  sourceId              String
  entityType            String              @db.VarChar(40)
  entityId              String              @db.VarChar(191)
  platformType          String              @db.VarChar(40)
  sourceUrl             String              @db.Text
  sourceContentId       String              @db.VarChar(191)
  capturedAt            DateTime
  occurredAt            DateTime?
  encryptedRawText      String?             @db.LongText
  rawTextIv             String?             @db.VarChar(64)
  rawTextAuthTag        String?             @db.VarChar(64)
  encryptionKeyVersion String?             @db.VarChar(40)
  sanitizedText         String?             @db.LongText
  normalizedTextHash    String              @db.Char(64)
  retentionUntil        DateTime
  processingStatus      ExperienceRawStatus @default(pending)
  createdAt             DateTime            @default(now())
  updatedAt             DateTime            @updatedAt

  run      ExperienceCollectionRun @relation(fields: [runId], references: [id], onDelete: Cascade)
  source   ContentSource            @relation(fields: [sourceId], references: [id], onDelete: Restrict)
  evidence ExperienceEvidence?

  @@unique([sourceId, sourceContentId, normalizedTextHash])
  @@index([processingStatus, retentionUntil])
  @@index([entityType, entityId, capturedAt])
  @@map("experience_raw_samples")
}

model ExperienceEvidence {
  id                    String                        @id @default(cuid())
  rawSampleId           String                        @unique
  entityType            String                        @db.VarChar(40)
  entityId              String                        @db.VarChar(191)
  institutionCode       String                        @db.VarChar(80)
  platformType          String                        @db.VarChar(40)
  sanitizedText         String                        @db.LongText
  safeSummary           String                        @db.Text
  primaryAspect         ExperienceAspect
  secondaryAspects      Json?
  sentiment             ExperienceSentiment
  sentimentIntensity    Int
  experienceTimeFrom    DateTime?
  experienceTimeTo      DateTime?
  qualityStatus         ExperienceQualityStatus
  qualityScore          Int
  credibilityScore      Decimal                       @db.Decimal(4, 2)
  clusterKey            String?                       @db.VarChar(191)
  analysisMetadata      Json?
  reviewStatus          ExperienceReviewStatus       @default(pending)
  reviewerUserId        String?                       @db.VarChar(191)
  reviewedAt            DateTime?
  reviewNote            String?                       @db.Text
  createdAt             DateTime                      @default(now())
  updatedAt             DateTime                      @updatedAt

  rawSample    ExperienceRawSample
    @relation(fields: [rawSampleId], references: [id], onDelete: Cascade)
  aggregateLinks ExperienceAggregateEvidence[]

  @@index([institutionCode, primaryAspect, reviewStatus])
  @@index([qualityStatus, reviewStatus])
  @@index([clusterKey])
  @@map("experience_evidence")
}

model ExperienceSignalAggregate {
  id                         String                  @id @default(cuid())
  entityType                 String                  @db.VarChar(40)
  entityId                   String                  @db.VarChar(191)
  institutionCode            String                  @db.VarChar(80)
  aspect                     ExperienceAspect
  windowStart                DateTime?
  windowEnd                  DateTime
  version                    Int                     @default(1)
  sentimentDistribution      Json
  recurringThemes            Json
  minorityViews              Json
  representativeSafeSummaries Json
  independentSourceCount     Int
  uniqueContentCount         Int
  duplicateSuppressionCount  Int
  qualityDistribution        Json
  sourcePlatformTypes        Json
  confidence                 Decimal                 @db.Decimal(4, 2)
  reviewStatus               ExperienceReviewStatus  @default(pending)
  reviewerUserId             String?                 @db.VarChar(191)
  reviewedAt                 DateTime?
  reviewNote                 String?                 @db.Text
  refreshedAt                DateTime                 @default(now())
  nextRefreshAt              DateTime
  publishedAt                DateTime?
  expiresAt                  DateTime?
  createdAt                  DateTime                 @default(now())
  updatedAt                  DateTime                 @updatedAt

  evidenceLinks ExperienceAggregateEvidence[]

  @@unique([entityType, entityId, aspect, windowEnd, version])
  @@index([institutionCode, reviewStatus, refreshedAt])
  @@index([publishedAt, expiresAt])
  @@map("experience_signal_aggregates")
}

model ExperienceAggregateEvidence {
  aggregateId String
  evidenceId  String
  weight      Decimal @db.Decimal(5, 4)
  createdAt   DateTime @default(now())

  aggregate ExperienceSignalAggregate
    @relation(fields: [aggregateId], references: [id], onDelete: Cascade)
  evidence  ExperienceEvidence
    @relation(fields: [evidenceId], references: [id], onDelete: Restrict)

  @@id([aggregateId, evidenceId])
  @@index([evidenceId])
  @@map("experience_aggregate_evidence")
}
```

- [ ] **Step 4: Write the matching SQL migration**

The migration must:

```sql
ALTER TABLE `content_sources`
  ADD COLUMN `sourceTier` ENUM('S1','S2','S3','S4') NULL,
  ADD COLUMN `contentFlowType` ENUM('fresh','experience') NULL,
  ADD COLUMN `accessMethod` ENUM(
    'public_page',
    'authenticated_public_page',
    'official_api',
    'authorized_export'
  ) NULL,
  ADD COLUMN `allowedScopes` JSON NULL,
  ADD COLUMN `forbiddenScopes` JSON NULL,
  ADD COLUMN `robotsReviewedAt` DATETIME(3) NULL,
  ADD COLUMN `termsReviewedAt` DATETIME(3) NULL,
  ADD COLUMN `nextPolicyReviewAt` DATETIME(3) NULL,
  ADD COLUMN `requestRatePerMinute` INTEGER NULL,
  ADD COLUMN `retentionPolicyVersion` VARCHAR(80) NULL;
```

Create the five new tables using the names from `@@map`, including the
`externalRunId + platformType` and sample-content unique keys, add every index
declared above, and add foreign keys with the same `onDelete` behavior. Do not
alter or delete existing community pilot rows.

- [ ] **Step 5: Validate and generate the Prisma client**

Run:

```powershell
Set-Location .backend_patch
npx prisma validate
npm run db:generate
npm test -- --run tests/unit/experienceSignalSchema.test.ts
```

Expected: schema valid, client generated, test PASS.

- [ ] **Step 6: Commit the schema task**

```powershell
git add .backend_patch/prisma .backend_patch/tests/unit/experienceSignalSchema.test.ts
git commit -m "feat: add experience signal data model"
```

---

### Task 2: Enforce source governance before collection

**Files:**
- Create: `.backend_patch/lib/experience-signals/contracts.ts`
- Create: `.backend_patch/lib/experience-signals/sourceGovernance.ts`
- Create: `.backend_patch/tests/unit/experienceSourceGovernance.test.ts`
- Modify: `.backend_patch/lib/content-ingestion/communitySources.ts`

**Interfaces:**
- Consumes: Prisma `ContentSource` and `ContentRightsSnapshot`.
- Produces:
  - `EXPERIENCE_ASPECTS`
  - `ExperiencePlatform`
  - `assertExperienceSourceAllowed(database, platform, now)`
  - `ExperienceSourcePermission`.

- [ ] **Step 1: Write the failing governance tests**

```ts
import { describe, expect, it, vi } from 'vitest';
import {
  ExperienceSourceBlockedError,
  assertExperienceSourceAllowed,
} from '@/lib/experience-signals/sourceGovernance';

describe('experience source governance', () => {
  it('fails closed when policy review is missing', async () => {
    const database = {
      contentSource: { findUnique: vi.fn().mockResolvedValue(null) },
    };
    await expect(
      assertExperienceSourceAllowed(database as never, 'zhihu', new Date()),
    ).rejects.toMatchObject({ reason: 'source_not_approved' });
  });

  it('allows only an active S4 experience source with valid rights', async () => {
    const database = {
      contentSource: {
        findUnique: vi.fn().mockResolvedValue({
          id: 'source-1',
          status: 'enabled',
          sourceTier: 'S4',
          contentFlowType: 'experience',
          accessMethod: 'authenticated_public_page',
          allowedScopes: ['public_post', 'public_comment'],
          forbiddenScopes: ['private_message', 'profile_identity'],
          requestRatePerMinute: 6,
          nextPolicyReviewAt: new Date('2026-12-01T00:00:00Z'),
          rightsSnapshots: [{
            id: 'rights-1',
            status: 'allowed',
            allowStoreMetadata: true,
            allowStoreExcerpt: true,
            allowStoreBody: true,
            allowStoreRawSnapshot: false,
            allowAiProcess: true,
            allowRecommend: true,
            effectiveAt: new Date('2026-07-31T00:00:00Z'),
            expiresAt: new Date('2026-12-01T00:00:00Z'),
          }],
        }),
      },
    };
    await expect(
      assertExperienceSourceAllowed(
        database as never,
        'zhihu',
        new Date('2026-08-01T00:00:00Z'),
      ),
    ).resolves.toMatchObject({
      sourceId: 'source-1',
      rightsSnapshotId: 'rights-1',
      allowStoreRawSnapshot: false,
    });
  });
});
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceSourceGovernance.test.ts
```

Expected: FAIL because the governance module does not exist.

- [ ] **Step 3: Define the shared experience contracts**

```ts
import { z } from 'zod';

export const EXPERIENCE_PLATFORMS = ['zhihu', 'tieba'] as const;
export const EXPERIENCE_ASPECTS = [
  'school_overall',
  'major_resources',
  'course_and_workload',
  'career_and_employment',
  'dormitory',
  'canteen',
  'clubs_and_culture',
] as const;
export const EXPERIENCE_RUN_STATUSES = [
  'queued',
  'running',
  'completed',
  'partial',
  'failed',
  'blocked',
] as const;

export type ExperiencePlatform = typeof EXPERIENCE_PLATFORMS[number];
export type ExperienceAspect = typeof EXPERIENCE_ASPECTS[number];

export const experiencePlatformSchema = z.enum(EXPERIENCE_PLATFORMS);
export const experienceAspectSchema = z.enum(EXPERIENCE_ASPECTS);
export const experienceRunStatusSchema = z.enum(EXPERIENCE_RUN_STATUSES);
```

- [ ] **Step 4: Implement a fail-closed governance check**

```ts
export type ExperienceSourcePermission = {
  sourceId: string;
  rightsSnapshotId: string;
  allowStoreRawSnapshot: boolean;
  rawRetentionDays: number;
  requestRatePerMinute: number;
};

export class ExperienceSourceBlockedError extends Error {
  constructor(
    public readonly reason:
      | 'source_not_approved'
      | 'source_paused'
      | 'policy_expired'
      | 'rights_not_allowed'
      | 'flow_mismatch',
  ) {
    super(reason);
    this.name = 'ExperienceSourceBlockedError';
  }
}

export async function assertExperienceSourceAllowed(
  database: ExperienceGovernanceDatabase,
  platform: ExperiencePlatform,
  now = new Date(),
): Promise<ExperienceSourcePermission> {
  const source = await database.contentSource.findUnique({
    where: { code: `experience-${platform}` },
    include: {
      rightsSnapshots: {
        orderBy: { effectiveAt: 'desc' },
        take: 1,
      },
    },
  });
  if (!source) throw new ExperienceSourceBlockedError('source_not_approved');
  if (source.status !== 'enabled') {
    throw new ExperienceSourceBlockedError('source_paused');
  }
  if (source.sourceTier !== 'S4' || source.contentFlowType !== 'experience') {
    throw new ExperienceSourceBlockedError('flow_mismatch');
  }
  if (source.nextPolicyReviewAt && source.nextPolicyReviewAt <= now) {
    throw new ExperienceSourceBlockedError('policy_expired');
  }
  const rights = source.rightsSnapshots[0];
  if (
    !rights
    || rights.status !== 'allowed'
    || !rights.allowAiProcess
    || !rights.allowRecommend
    || (rights.expiresAt && rights.expiresAt <= now)
  ) {
    throw new ExperienceSourceBlockedError('rights_not_allowed');
  }
  return {
    sourceId: source.id,
    rightsSnapshotId: rights.id,
    allowStoreRawSnapshot: rights.allowStoreRawSnapshot,
    rawRetentionDays: Math.min(Math.max(source.rawRetentionDays, 0), 30),
    requestRatePerMinute: Math.min(
      Math.max(source.requestRatePerMinute ?? 6, 1),
      12,
    ),
  };
}
```

`communitySources.ts` must only contain platform host definitions and display
metadata. Remove the code path that silently creates an `allowed` rights
snapshot during ingestion.

- [ ] **Step 5: Run the governance tests**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceSourceGovernance.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit the governance task**

```powershell
git add .backend_patch/lib/experience-signals .backend_patch/lib/content-ingestion/communitySources.ts .backend_patch/tests/unit/experienceSourceGovernance.test.ts
git commit -m "feat: gate experience collection by source policy"
```

---

### Task 3: Persist run reports and optionally encrypted raw samples

**Files:**
- Create: `.backend_patch/lib/experience-signals/rawCrypto.ts`
- Create: `.backend_patch/lib/experience-signals/repository.ts`
- Create: `.backend_patch/tests/unit/experienceRawCrypto.test.ts`
- Create: `.backend_patch/tests/unit/experienceRunIngestion.test.ts`
- Modify: `.backend_patch/lib/content-ingestion/communityIngestion.ts`
- Modify: `.backend_patch/app/api/internal/content-ingestion/community/route.ts`

**Interfaces:**
- Consumes: `ExperienceSourcePermission`.
- Produces:
  - `experienceRunReportSchema`
  - `encryptExperienceRawText(plaintext, keyConfig)`
  - `ingestExperienceRunReport(prisma, payload)`.

- [ ] **Step 1: Write failing encryption and zero-sample run tests**

```ts
import { describe, expect, it } from 'vitest';
import {
  decryptExperienceRawText,
  encryptExperienceRawText,
} from '@/lib/experience-signals/rawCrypto';

describe('experience raw encryption', () => {
  it('round-trips with AES-256-GCM without returning plaintext fields', () => {
    const key = Buffer.alloc(32, 7).toString('base64');
    const encrypted = encryptExperienceRawText('含手机号 13800138000', {
      keyBase64: key,
      keyVersion: 'v1',
    });
    expect(JSON.stringify(encrypted)).not.toContain('13800138000');
    expect(decryptExperienceRawText(encrypted, { keyBase64: key })).toBe(
      '含手机号 13800138000',
    );
  });
});
```

```ts
it('records a blocked run even when no samples were collected', async () => {
  const payload = {
    runId: 'community-agent-blocked-001',
    institutionCode: 'peking-university',
    institutionName: '北京大学',
    platform: 'zhihu',
    trigger: 'manual',
    discoveryMode: 'agent',
    status: 'blocked',
    counters: { plannedTasks: 1, blockedTasks: 1, uploaded: 0 },
    blockReasons: ['captcha'],
    startedAt: '2026-07-31T01:00:00.000Z',
    completedAt: '2026-07-31T01:01:00.000Z',
    documents: [],
  };
  await ingestExperienceRunReport(database as never, payload);
  expect(database.experienceCollectionRun.upsert).toHaveBeenCalledWith(
    expect.objectContaining({
      create: expect.objectContaining({ status: 'blocked' }),
    }),
  );
  expect(database.experienceRawSample.upsert).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceRawCrypto.test.ts tests/unit/experienceRunIngestion.test.ts
```

Expected: FAIL because the modules and new ingestion function do not exist.

- [ ] **Step 3: Implement AES-256-GCM helpers**

```ts
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from 'node:crypto';

export type EncryptedExperienceRawText = {
  encryptedRawText: string;
  rawTextIv: string;
  rawTextAuthTag: string;
  encryptionKeyVersion: string;
};

function readKey(keyBase64: string) {
  const key = Buffer.from(keyBase64, 'base64');
  if (key.length !== 32) {
    throw new Error('EXPERIENCE_RAW_ENCRYPTION_KEY must decode to 32 bytes.');
  }
  return key;
}

export function encryptExperienceRawText(
  plaintext: string,
  config: { keyBase64: string; keyVersion: string },
): EncryptedExperienceRawText {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', readKey(config.keyBase64), iv);
  const ciphertext = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  return {
    encryptedRawText: ciphertext.toString('base64'),
    rawTextIv: iv.toString('base64'),
    rawTextAuthTag: cipher.getAuthTag().toString('base64'),
    encryptionKeyVersion: config.keyVersion,
  };
}
```

Add the inverse `decryptExperienceRawText` only for restricted admin and test
use. It must require a key and authenticate the GCM tag.

- [ ] **Step 4: Define the run report schema**

```ts
export const experienceRunReportSchema = z.object({
  runId: z.string().trim().min(8).max(191),
  institutionCode: z.literal('peking-university'),
  institutionName: z.literal('北京大学'),
  platform: experiencePlatformSchema,
  trigger: z.enum(['manual', 'scheduled']).default('manual'),
  discoveryMode: z.enum(['agent', 'search_api']),
  status: experienceRunStatusSchema,
  counters: z.record(z.string().max(60), z.number().int().min(0)).default({}),
  blockReasons: z.array(z.string().trim().min(1).max(120)).max(30).default([]),
  startedAt: z.string().datetime(),
  completedAt: z.string().datetime().nullable(),
  documents: z.array(experienceDocumentSchema).max(50).default([]),
}).strict();
```

Map the old dimensions at the API boundary:

```ts
const LEGACY_ASPECT_MAP = {
  school: 'school_overall',
  major: 'major_resources',
  course: 'course_and_workload',
  employment: 'career_and_employment',
  dormitory: 'dormitory',
  cafeteria: 'canteen',
  student_club: 'clubs_and_culture',
} as const;
```

- [ ] **Step 5: Implement idempotent run/sample persistence**

`ingestExperienceRunReport` must:

```ts
const permission = await assertExperienceSourceAllowed(
  prisma,
  payload.platform,
);
const run = await prisma.experienceCollectionRun.upsert({
  where: {
    externalRunId_platformType: {
      externalRunId: payload.runId,
      platformType: payload.platform,
    },
  },
  create: {
    externalRunId: payload.runId,
    platformType: payload.platform,
    entityType: 'school',
    entityId: payload.institutionCode,
    institutionCode: payload.institutionCode,
    trigger: payload.trigger,
    discoveryMode: payload.discoveryMode,
    status: payload.status,
    counters: payload.counters,
    blockReasons: payload.blockReasons,
    startedAt: new Date(payload.startedAt),
    completedAt: payload.completedAt
      ? new Date(payload.completedAt)
      : null,
  },
  update: {
    status: payload.status,
    counters: payload.counters,
    blockReasons: payload.blockReasons,
    completedAt: payload.completedAt
      ? new Date(payload.completedAt)
      : null,
  },
});
```

For each document, run the existing deterministic `cleanCommunityEvidence`
before persistence so plaintext PII is never queued. Save its redacted result
to `ExperienceRawSample.sanitizedText` for the asynchronous analyzer; Task 4
will replace this compatibility call with the final experience cleaner. Only
populate the four encryption columns when both `allowStoreRawSnapshot` is true
and `rawRetentionDays > 0`; otherwise save only the hash and sanitized text.
Use a transaction and the unique tuple
`sourceId_sourceContentId_normalizedTextHash` so a network retry is unchanged,
not duplicated.

The internal route continues to use existing crawler-token authorization and
Zod validation. It must accept an empty `documents` array so blocked runs are
visible.

- [ ] **Step 6: Run the ingestion tests**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceRawCrypto.test.ts tests/unit/experienceRunIngestion.test.ts
```

Expected: PASS, including the assertion that disabled raw retention never sends
plaintext into a Prisma write.

- [ ] **Step 7: Commit the run ingestion task**

```powershell
git add .backend_patch/lib/experience-signals .backend_patch/lib/content-ingestion/communityIngestion.ts .backend_patch/app/api/internal/content-ingestion/community/route.ts .backend_patch/tests/unit/experienceRawCrypto.test.ts .backend_patch/tests/unit/experienceRunIngestion.test.ts
git commit -m "feat: record experience collection runs safely"
```

---

### Task 4: Clean and structure experience evidence

**Files:**
- Create: `.backend_patch/lib/experience-signals/cleaner.ts`
- Create: `.backend_patch/lib/experience-signals/analyzer.ts`
- Create: `.backend_patch/tests/unit/experienceCleaner.test.ts`
- Create: `.backend_patch/tests/unit/experienceAnalyzer.test.ts`
- Modify: `.backend_patch/lib/community-analysis/contracts.ts`
- Modify: `.backend_patch/lib/community-analysis/analyzer.ts`
- Modify: `.backend_patch/scripts/workers/community-evidence-analysis-worker.ts`

**Interfaces:**
- Consumes: `ExperienceRawSample` text in memory and `ExperienceAspect`.
- Produces:
  - `cleanExperienceSample(input): ExperienceCleaningResult`
  - `analyzeExperienceEvidence(input, aiCall): ExperienceAnalysisResult`
  - pending `ExperienceEvidence`.

- [ ] **Step 1: Write failing cleaner tests**

```ts
import { describe, expect, it } from 'vitest';
import { cleanExperienceSample } from '@/lib/experience-signals/cleaner';

describe('experience cleaner', () => {
  it('redacts direct identifiers and keeps useful experience', () => {
    const result = cleanExperienceSample({
      text: '我在北大住过三年，宿舍公共空间较小。手机号13800138000。',
      title: '宿舍体验',
      suggestedAspect: 'dormitory',
    });
    expect(result.decision).toBe('review_required');
    expect(result.sanitizedText).not.toContain('13800138000');
    expect(result.privacyFlags).toContain('phone');
  });

  it.each(['哈哈哈哈', '666', '加微信 abc123 报名享优惠'])(
    'rejects low-value or promotional text: %s',
    (text) => {
      expect(cleanExperienceSample({
        text,
        title: '测试',
        suggestedAspect: 'school_overall',
      }).decision).toBe('rejected');
    },
  );
});
```

- [ ] **Step 2: Write the failing analyzer contract test**

```ts
it('requires one primary aspect, bounded secondary aspects and safe summary', async () => {
  const result = await analyzeExperienceEvidence(input, async () => ({
    content: JSON.stringify({
      primaryAspect: 'course_and_workload',
      secondaryAspects: ['major_resources'],
      safeSummary: '课程任务较重，同时能接触较多专业资源。',
      sentiment: 'mixed',
      sentimentIntensity: 65,
      experienceTimeFrom: '2022-09-01T00:00:00.000Z',
      experienceTimeTo: '2026-06-30T00:00:00.000Z',
      informationValue: 8,
      credibility: 7.5,
      qualityStatus: 'high_value',
      recurringTheme: '课程强度与资源',
      riskReasons: [],
      requiresHumanReview: true,
    }),
    model: 'test-model',
    latencyMs: 1,
  }));
  expect(result.primaryAspect).toBe('course_and_workload');
  expect(result.requiresHumanReview).toBe(true);
});
```

- [ ] **Step 3: Run both tests and confirm they fail**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceCleaner.test.ts tests/unit/experienceAnalyzer.test.ts
```

Expected: FAIL because the new cleaner and analyzer do not exist.

- [ ] **Step 4: Implement deterministic cleaning**

Move reusable normalization, spam patterns, PII redaction and similarity hash
logic from `communityCleaner.ts` into `experience-signals/cleaner.ts`.

The returned type must be:

```ts
export type ExperienceCleaningResult = {
  decision: 'rejected' | 'review_required';
  sanitizedText: string;
  qualityStatus:
    | 'usable'
    | 'low_context'
    | 'spam'
    | 'unsafe';
  qualityScore: number;
  spamSignals: string[];
  privacyFlags: string[];
  safetyFlags: string[];
  normalizedTextHash: string;
  similarityHash: string;
};
```

Rules must run in this order: Unicode/HTML normalization, direct-identifier
redaction, solicitation and promotion filtering, low-information filtering,
unsafe-content marking, hash calculation. AI must never receive the pre-redacted
text.

- [ ] **Step 5: Implement strict AI analysis**

Use this Zod shape:

```ts
export const experienceAnalysisSchema = z.object({
  primaryAspect: experienceAspectSchema,
  secondaryAspects: z.array(experienceAspectSchema).max(3),
  safeSummary: z.string().trim().min(8).max(300),
  sentiment: z.enum(['positive', 'neutral', 'mixed', 'negative']),
  sentimentIntensity: z.number().int().min(0).max(100),
  experienceTimeFrom: z.string().datetime().nullable(),
  experienceTimeTo: z.string().datetime().nullable(),
  informationValue: z.number().int().min(0).max(10),
  credibility: z.number().min(0).max(10),
  qualityStatus: z.enum(['high_value', 'usable', 'low_context', 'unsafe']),
  recurringTheme: z.string().trim().min(2).max(120),
  riskReasons: z.array(z.string().trim().min(1).max(120)).max(10),
  requiresHumanReview: z.literal(true),
}).strict();
```

The system prompt must say:

```text
只分析已脱敏文本；不得推断作者身份。
不得把一条体验推断成学校整体事实。
必须从七个枚举中选择一个主维度，次维度最多三个。
safeSummary 必须删除身份线索、辱骂和无法核验的绝对化结论。
requiresHumanReview 必须为 true。
只返回 JSON。
```

- [ ] **Step 6: Update the worker to write pending evidence**

The worker sequence must be:

```ts
const cleaned = cleanExperienceSample({
  title: rawSampleTitle,
  text: rawSample.sanitizedText ?? '',
  suggestedAspect,
});
if (cleaned.decision === 'rejected') {
  await repository.rejectRawSample(rawSampleId, cleaned);
  return;
}
const analysis = await analyzeExperienceEvidence({
  sanitizedText: cleaned.sanitizedText,
  suggestedAspect,
  institutionCode: 'peking-university',
  institutionName: '北京大学',
  platform,
}, callDeepSeekJson);
await repository.savePendingEvidence(rawSampleId, cleaned, analysis);
```

Do not set aggregate or App publication status in this worker.

- [ ] **Step 7: Run the focused tests**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceCleaner.test.ts tests/unit/experienceAnalyzer.test.ts tests/unit/communityEvidenceQueue.test.ts
```

Expected: PASS.

- [ ] **Step 8: Commit the cleaning and analysis task**

```powershell
git add .backend_patch/lib/experience-signals .backend_patch/lib/community-analysis .backend_patch/scripts/workers/community-evidence-analysis-worker.ts .backend_patch/tests/unit/experienceCleaner.test.ts .backend_patch/tests/unit/experienceAnalyzer.test.ts
git commit -m "feat: structure cleaned experience evidence"
```

---

### Task 5: Aggregate only approved evidence

**Files:**
- Create: `.backend_patch/lib/experience-signals/aggregator.ts`
- Create: `.backend_patch/tests/unit/experienceAggregator.test.ts`
- Modify: `.backend_patch/lib/experience-signals/repository.ts`

**Interfaces:**
- Consumes: approved `ExperienceEvidence` rows for one school and time window.
- Produces:
  - `buildExperienceAggregate(input): ExperienceAggregateDraft`
  - `recomputeExperienceAggregates(database, institutionCode, now)`.

- [ ] **Step 1: Write the failing aggregation tests**

```ts
import { describe, expect, it } from 'vitest';
import { buildExperienceAggregate } from '@/lib/experience-signals/aggregator';

describe('experience aggregation', () => {
  it('suppresses duplicate clusters and preserves minority views', () => {
    const result = buildExperienceAggregate({
      institutionCode: 'peking-university',
      aspect: 'dormitory',
      evidence: [
        evidence('e1', 'zhihu', 'cluster-a', 'negative', '宿舍空间较小', 8),
        evidence('e2', 'tieba', 'cluster-a', 'negative', '宿舍空间较小', 7),
        evidence('e3', 'tieba', 'cluster-b', 'positive', '公共区域维护较好', 6),
      ],
      windowEnd: new Date('2026-07-31T00:00:00Z'),
    });
    expect(result.uniqueContentCount).toBe(2);
    expect(result.duplicateSuppressionCount).toBe(1);
    expect(result.minorityViews).toContain('公共区域维护较好');
    expect(result.reviewStatus).toBe('pending');
  });

  it('does not convert sample counts into population percentages', () => {
    const result = buildExperienceAggregate(input);
    expect(JSON.stringify(result)).not.toMatch(/%|百分之|学生都/);
  });
});
```

The test helper `evidence` must return a complete typed fixture with
`reviewStatus: 'approved'`, quality/credibility scores and timestamps.

- [ ] **Step 2: Run the test and confirm it fails**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceAggregator.test.ts
```

Expected: FAIL because the aggregator does not exist.

- [ ] **Step 3: Implement deterministic aggregation**

```ts
export type ExperienceAggregateDraft = {
  entityType: 'school';
  entityId: 'peking-university';
  institutionCode: 'peking-university';
  aspect: ExperienceAspect;
  windowStart: Date | null;
  windowEnd: Date;
  sentimentDistribution: {
    positive: number;
    neutral: number;
    mixed: number;
    negative: number;
  };
  recurringThemes: string[];
  minorityViews: string[];
  representativeSafeSummaries: string[];
  independentSourceCount: number;
  uniqueContentCount: number;
  duplicateSuppressionCount: number;
  qualityDistribution: Record<string, number>;
  sourcePlatformTypes: string[];
  confidence: number;
  reviewStatus: 'pending';
  nextRefreshAt: Date;
  evidenceWeights: Array<{ evidenceId: string; weight: number }>;
};
```

Aggregation rules:

```ts
const representativeByCluster = pickHighestWeightedEvidencePerCluster(input.evidence);
const independentPlatforms = new Set(
  representativeByCluster.map((item) => item.platformType),
);
const confidence = Math.min(10, (
  Math.log2(representativeByCluster.length + 1) * 1.8
  + independentPlatforms.size * 1.2
  + average(representativeByCluster.map((item) => item.credibilityScore)) * 0.45
));
```

Use counts for `sentimentDistribution`. A recurring theme requires at least two
distinct clusters. A minority view is a non-dominant theme with at least one
approved representative; label it as a sampled minority view, not a population
ratio. `nextRefreshAt` is six months after `windowEnd` for the first phase.

- [ ] **Step 4: Persist one versioned pending aggregate per aspect**

`recomputeExperienceAggregates` must:

1. Query only `reviewStatus = approved`.
2. Exclude `duplicate`, `spam`, `unsafe`, `low_context`.
3. Build all seven aspects in memory.
4. In one transaction, create the next version and its join rows.
5. Leave earlier approved versions unchanged for audit.
6. Never set `publishedAt` before aggregate review.

Use:

```ts
await transaction.experienceSignalAggregate.create({
  data: {
    ...draftWithoutEvidenceWeights,
    version: latestVersion + 1,
    reviewStatus: 'pending',
    evidenceLinks: {
      create: draft.evidenceWeights.map((entry) => ({
        evidenceId: entry.evidenceId,
        weight: entry.weight,
      })),
    },
  },
});
```

- [ ] **Step 5: Run the aggregation tests**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceAggregator.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit the aggregation task**

```powershell
git add .backend_patch/lib/experience-signals/aggregator.ts .backend_patch/lib/experience-signals/repository.ts .backend_patch/tests/unit/experienceAggregator.test.ts
git commit -m "feat: aggregate approved school experiences"
```

---

### Task 6: Add admin governance, evidence and aggregate APIs

**Files:**
- Create: `.backend_patch/lib/adminExperienceSignals.ts`
- Create: `.backend_patch/app/api/admin/content-ingestion/experience-signals/route.ts`
- Create: `.backend_patch/app/api/admin/content-ingestion/experience-signals/[resourceId]/route.ts`
- Create: `.backend_patch/app/api/admin/content-ingestion/experience-signals/recompute/route.ts`
- Create: `.backend_patch/app/api/admin/content-ingestion/experience-sources/[sourceCode]/route.ts`
- Create: `.backend_patch/tests/unit/adminExperienceSignals.test.ts`

**Interfaces:**
- Consumes: experience models and `requireAdminSession`.
- Produces:
  - `getExperienceAdminDashboard(query, database)`
  - `reviewExperienceEvidence(...)`
  - `reviewExperienceAggregate(...)`
  - `reviewExperienceSourcePolicy(...)`.

- [ ] **Step 1: Write failing service tests**

```ts
it('returns run, evidence, aggregate and governance summaries without raw text', async () => {
  const result = await getExperienceAdminDashboard(
    { institutionCode: 'peking-university' },
    database as never,
  );
  expect(result.summary).toMatchObject({
    runs: 2,
    pendingEvidence: 4,
    pendingAggregates: 7,
  });
  expect(JSON.stringify(result)).not.toContain('encryptedRawText');
  expect(JSON.stringify(result)).not.toContain('rawTextAuthTag');
});

it('publishes an aggregate only after explicit admin approval', async () => {
  await reviewExperienceAggregate(
    'aggregate-1',
    {
      action: 'approve',
      expectedUpdatedAt: '2026-07-31T03:00:00.000Z',
      note: '首批抽样核对通过',
    },
    'admin-1',
    database as never,
  );
  expect(transaction.experienceSignalAggregate.update).toHaveBeenCalledWith(
    expect.objectContaining({
      data: expect.objectContaining({
        reviewStatus: 'approved',
        publishedAt: expect.any(Date),
      }),
    }),
  );
});
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/adminExperienceSignals.test.ts
```

Expected: FAIL because the admin service does not exist.

- [ ] **Step 3: Implement admin contracts and transactions**

Use strict Zod schemas:

```ts
export const experienceAdminQuerySchema = z.object({
  institutionCode: z.literal('peking-university').default('peking-university'),
  view: z.enum(['runs', 'evidence', 'aggregates', 'sources']).default('runs'),
  status: z.string().trim().max(40).optional(),
  platform: z.enum(['zhihu', 'tieba']).optional(),
  aspect: experienceAspectSchema.optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(50).default(20),
}).strict();

export const experienceReviewSchema = z.object({
  resourceType: z.enum(['evidence', 'aggregate']),
  action: z.enum(['approve', 'reject']),
  expectedUpdatedAt: z.string().datetime(),
  note: z.string().trim().min(2).max(1_000),
}).strict();
```

Every mutation must:

- call `assertSafeMutationRequest`;
- require an admin session;
- compare `expectedUpdatedAt`;
- update in a transaction;
- create an `auditLog`;
- return `409` on concurrent modification.

Evidence approval makes the evidence eligible for recompute but does not publish
it. Aggregate approval sets `publishedAt`; aggregate rejection leaves all
evidence intact.

- [ ] **Step 4: Add source-policy review**

The source mutation body is:

```ts
const sourcePolicyReviewSchema = z.object({
  decision: z.enum(['allow', 'pause']),
  evidenceUrl: z.string().url().max(8_192),
  note: z.string().trim().min(10).max(2_000),
  effectiveAt: z.string().datetime(),
  expiresAt: z.string().datetime(),
  allowStoreRawSnapshot: z.boolean().default(false),
  rawRetentionDays: z.number().int().min(0).max(30).default(0),
}).strict();
```

For `allow`, set source governance to `S4`, `experience`,
`authenticated_public_page`, status `enabled`, request rate no higher than six
per minute, and create a new rights snapshot. For `pause`, set status `paused`
and do not create an allowed snapshot. Both actions require an audit row.

- [ ] **Step 5: Add authenticated API routes**

GET returns the selected view. PATCH dispatches by `resourceType`. POST
`recompute` calls `recomputeExperienceAggregates` only after at least one
approved evidence row exists. No API response may include raw ciphertext,
identity data or model reasoning.

- [ ] **Step 6: Run the admin service and route tests**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/adminExperienceSignals.test.ts tests/unit/communityEvidenceAdminPage.test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit the admin API task**

```powershell
git add .backend_patch/lib/adminExperienceSignals.ts .backend_patch/app/api/admin/content-ingestion .backend_patch/tests/unit/adminExperienceSignals.test.ts
git commit -m "feat: add experience review administration APIs"
```

---

### Task 7: Build the existing admin center experience workspace

**Files:**
- Create: `.backend_patch/app/admin/content-ingestion/ExperienceSignalsClient.tsx`
- Modify: `.backend_patch/app/admin/content-ingestion/community-evidence/page.tsx`
- Modify: `.backend_patch/app/admin/content-ingestion/AdminContentIngestionDashboardClient.tsx`
- Modify: `.backend_patch/tests/unit/communityEvidenceAdminPage.test.ts`

**Interfaces:**
- Consumes: Task 6 admin APIs.
- Produces: four tabs inside the existing content monitoring area.

- [ ] **Step 1: Extend the failing page test**

```ts
it('keeps experience management inside the content ingestion center', () => {
  const page = readFileSync(
    'app/admin/content-ingestion/community-evidence/page.tsx',
    'utf8',
  );
  const client = readFileSync(
    'app/admin/content-ingestion/ExperienceSignalsClient.tsx',
    'utf8',
  );
  expect(page).toContain('学校体验语料');
  expect(client).toContain('采集运行');
  expect(client).toContain('证据审核');
  expect(client).toContain('体验聚合');
  expect(client).toContain('来源治理');
  expect(client).not.toContain('邀请码');
});
```

- [ ] **Step 2: Run the page test and confirm it fails**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/communityEvidenceAdminPage.test.ts
```

Expected: FAIL because `ExperienceSignalsClient.tsx` does not exist.

- [ ] **Step 3: Implement the four-tab client**

Use this top-level state shape:

```ts
type ExperienceAdminTab = 'runs' | 'evidence' | 'aggregates' | 'sources';

const TABS: Array<{ id: ExperienceAdminTab; label: string }> = [
  { id: 'runs', label: '采集运行' },
  { id: 'evidence', label: '证据审核' },
  { id: 'aggregates', label: '体验聚合' },
  { id: 'sources', label: '来源治理' },
];
```

The UI must show:

- runs: `completed / partial / blocked / failed`, counts, block reason,
  started/completed duration;
- evidence: platform, aspect, sanitized text, safe summary, quality,
  credibility, approve/reject;
- aggregates: time window, source platform count, sample count, duplicate
  suppression, sentiment counts, recurring themes, minority views, confidence,
  approve/reject/recompute;
- sources: tier, flow, access method, policy review dates, retention, status,
  allow/pause.

Do not expose encrypted raw fields. Use user-facing labels such as “访问受限”
instead of dumping exception strings.

- [ ] **Step 4: Wire the existing page and dashboard link**

The server page keeps the existing admin-role guard, loads the initial
`runs` view, and renders `ExperienceSignalsClient`. The main content ingestion
dashboard changes only the existing community entry label and link; no other
cards or routes are changed.

- [ ] **Step 5: Run page tests and backend typecheck**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/communityEvidenceAdminPage.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 6: Commit the admin UI task**

```powershell
git add .backend_patch/app/admin/content-ingestion .backend_patch/tests/unit/communityEvidenceAdminPage.test.ts
git commit -m "feat: add school experience review workspace"
```

---

### Task 8: Attach the local Agent to an already logged-in Chrome

**Files:**
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_browser.py`
- Create: `.crawler_scaffold/university-crawler/tests/test_community_browser.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/config.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_agent.py`
- Modify: `.crawler_scaffold/university-crawler/tests/test_community_agent.py`

**Interfaces:**
- Consumes: `COMMUNITY_AGENT_CDP_URL`.
- Produces:
  - `validate_loopback_cdp_url(value) -> str`
  - `CommunityBrowserMode`
  - Browser Use runtime that calls `stop()` for attached Chrome and `kill()`
    only for Agent-owned Chromium.

- [ ] **Step 1: Write failing CDP validation tests**

```py
import pytest
from university_crawler.community_browser import validate_loopback_cdp_url

@pytest.mark.parametrize("url", [
    "http://127.0.0.1:9222",
    "http://localhost:9222",
    "http://[::1]:9222",
])
def test_accepts_loopback_cdp(url: str) -> None:
    assert validate_loopback_cdp_url(url) == url

@pytest.mark.parametrize("url", [
    "http://192.168.1.5:9222",
    "http://101.132.100.225:9222",
    "https://example.com:9222",
])
def test_rejects_non_loopback_cdp(url: str) -> None:
    with pytest.raises(ValueError, match="loopback"):
        validate_loopback_cdp_url(url)
```

- [ ] **Step 2: Write the failing browser ownership test**

```py
async def test_attached_browser_is_stopped_but_not_killed() -> None:
    browser = FakeBrowser()
    runtime = build_runtime(
        cdp_url="http://127.0.0.1:9222",
        browser=browser,
    )
    await runtime.close()
    assert browser.stop_calls == 1
    assert browser.kill_calls == 0
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run:

```powershell
Set-Location .crawler_scaffold/university-crawler
.\.venv\Scripts\python.exe -m pytest tests/test_community_browser.py tests/test_community_agent.py -q
```

Expected: FAIL because loopback validation and attached-browser ownership do
not exist.

- [ ] **Step 4: Implement loopback-only validation**

```py
from dataclasses import dataclass
from urllib.parse import urlparse

LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}

def validate_loopback_cdp_url(value: str) -> str:
    normalized = value.strip()
    if not normalized:
      return ""
    parsed = urlparse(normalized)
    if parsed.scheme != "http" or parsed.hostname not in LOOPBACK_HOSTS:
        raise ValueError("COMMUNITY_AGENT_CDP_URL must use HTTP loopback.")
    if parsed.port is None:
        raise ValueError("COMMUNITY_AGENT_CDP_URL must include a port.")
    return normalized

@dataclass(frozen=True)
class CommunityBrowserMode:
    cdp_url: str
    owns_process: bool
```

Add to `Settings`:

```py
community_agent_cdp_url: str = ""
```

Validate it before Browser Use is imported or any network task starts.

- [ ] **Step 5: Attach Browser Use to the existing Chrome**

Build browser options as:

```py
cdp_url = validate_loopback_cdp_url(settings.community_agent_cdp_url)
if cdp_url:
    browser_options = {
        "cdp_url": cdp_url,
        "allowed_domains": list(PLATFORM_HOSTS[task.platform]),
        "keep_alive": True,
        "captcha_solver": False,
    }
    self._owns_browser_process = False
else:
    browser_options = {
        "headless": settings.community_agent_browser_headless,
        "allowed_domains": list(PLATFORM_HOSTS[task.platform]),
        "keep_alive": False,
        "captcha_solver": False,
    }
    self._owns_browser_process = True
```

Close with:

```py
async def close(self) -> None:
    if self._owns_browser_process:
        await self._browser.kill()
    else:
        # CDP 浏览器属于用户；这里只断开 Agent 会话，不能关闭 Chrome。
        await self._browser.stop()
```

No cookie, profile path or browser storage value may appear in the task result
or upload payload.

- [ ] **Step 6: Run crawler browser tests**

Run:

```powershell
Set-Location .crawler_scaffold/university-crawler
.\.venv\Scripts\python.exe -m pytest tests/test_community_browser.py tests/test_community_agent.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit the local browser task**

```powershell
git add .crawler_scaffold/university-crawler/src/university_crawler .crawler_scaffold/university-crawler/tests/test_community_browser.py .crawler_scaffold/university-crawler/tests/test_community_agent.py
git commit -m "feat: attach experience agent to local chrome"
```

---

### Task 9: Report blocked and partial local runs accurately

**Files:**
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_models.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_ingestion.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_runner.py`
- Modify: `.crawler_scaffold/university-crawler/tests/test_community_ingestion.py`
- Modify: `.crawler_scaffold/university-crawler/tests/test_community_runner.py`
- Create: `tool/run_experience_snapshot.ps1`
- Create: `docs/operations/experience-snapshot-runbook.md`

**Interfaces:**
- Consumes: Task 3 backend run-report API and Task 8 local CDP runtime.
- Produces:
  - final states `COMPLETED`, `PARTIAL`, `BLOCKED`, `FAILED`;
  - one final run report even when `documents=[]`;
  - a local manual launcher.

- [ ] **Step 1: Write failing runner status tests**

```py
async def test_all_blocked_tasks_report_blocked() -> None:
    result = await run_with_results([
        task_result("blocked_captcha"),
        task_result("blocked_access"),
    ])
    assert result.state == "BLOCKED"
    assert result.exit_code == 0
    uploader.assert_awaited_once()
    assert uploader.call_args.kwargs["documents"] == []
    assert uploader.call_args.kwargs["status"] == "blocked"

async def test_mixed_success_and_block_is_partial() -> None:
    result = await run_with_results([
        task_result("completed", candidates=[candidate()]),
        task_result("blocked_access"),
    ])
    assert result.state == "PARTIAL"
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:

```powershell
Set-Location .crawler_scaffold/university-crawler
.\.venv\Scripts\python.exe -m pytest tests/test_community_runner.py tests/test_community_ingestion.py -q
```

Expected: FAIL because the current runner reports all-blocked as `COMPLETED`.

- [ ] **Step 3: Add a final run report model**

```py
CommunityRunState = Literal["completed", "partial", "failed", "blocked"]

class CommunityRunReport(BaseModel):
    run_id: str
    institution_code: Literal["peking-university"]
    institution_name: Literal["北京大学"]
    platform: CommunityPlatform
    trigger: Literal["manual", "scheduled"]
    discovery_mode: Literal["agent", "search_api"]
    status: CommunityRunState
    counters: dict[str, int]
    block_reasons: list[str] = Field(default_factory=list)
    started_at: datetime
    completed_at: datetime
    documents: list[CommunityEvidenceCandidate] = Field(default_factory=list)
```

- [ ] **Step 4: Calculate the top-level state from task outcomes**

```py
def classify_run_state(counts: dict[str, int]) -> CommunityRunState:
    planned = counts["planned_tasks"]
    completed = counts["completed_tasks"]
    blocked = counts["blocked_tasks"]
    failed = counts["failed_tasks"]
    if planned > 0 and blocked == planned:
        return "blocked"
    if completed > 0 and (blocked > 0 or failed > 0):
        return "partial"
    if completed == 0 and failed > 0:
        return "failed"
    return "completed"
```

Always call the final report endpoint once per platform. Chunked sample uploads
may happen first, but the final empty/non-empty report owns the final counters
and status.

- [ ] **Step 5: Add the Windows manual launcher**

`tool/run_experience_snapshot.ps1` must:

```powershell
param(
  [ValidateSet('all','zhihu','tieba')]
  [string]$Platform = 'all',
  [ValidateSet('all','school','major','course','employment','dormitory','cafeteria','student_club')]
  [string]$Dimension = 'all'
)

$ErrorActionPreference = 'Stop'
$crawlerRoot = Join-Path $PSScriptRoot '..\.crawler_scaffold\university-crawler'
$python = Join-Path $crawlerRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
  throw '本地采集器虚拟环境不存在。'
}
if (-not (Test-NetConnection 127.0.0.1 -Port 9222 -InformationLevel Quiet)) {
  throw '专用 Chrome 的 9222 调试端口未启动。'
}

Push-Location $crawlerRoot
try {
  & $python -m university_crawler.main --community `
    --institution peking-university `
    --platform $Platform `
    --discovery-mode agent `
    --dimension $Dimension
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
```

The runbook must include the dedicated Chrome launch command, login check,
source-policy prerequisite, launcher examples, admin review path and blocked
state explanations. It must explicitly say the ECS community timer remains
disabled.

- [ ] **Step 6: Run the runner tests**

Run:

```powershell
Set-Location .crawler_scaffold/university-crawler
.\.venv\Scripts\python.exe -m pytest tests/test_community_runner.py tests/test_community_ingestion.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit the run reporting task**

```powershell
git add .crawler_scaffold/university-crawler/src/university_crawler .crawler_scaffold/university-crawler/tests tool/run_experience_snapshot.ps1 docs/operations/experience-snapshot-runbook.md
git commit -m "feat: report local experience snapshot outcomes"
```

---

### Task 10: Search published aggregates and render them correctly in App

**Files:**
- Create: `.backend_patch/lib/experience-signals/search.ts`
- Create: `.backend_patch/tests/unit/experienceSignalSearch.test.ts`
- Modify: `.backend_patch/lib/content-library/storedAnswer.ts`
- Modify: `.backend_patch/lib/content-sources/sourceTypes.ts`
- Modify: `.backend_patch/lib/content-sources/unifiedAnswer.ts`
- Modify: `.backend_patch/tests/unit/unifiedAnswer.test.ts`
- Modify: `lib/unified_content_answer_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: approved/published `ExperienceSignalAggregate`.
- Produces:
  - `searchPublishedExperienceSignals(input, database)`
  - `UnifiedContentItem.presentation`
  - Flutter `UnifiedAnswerSource.presentation`.

- [ ] **Step 1: Write the failing backend search test**

```ts
it('returns only approved, published and unexpired aggregates', async () => {
  const result = await searchPublishedExperienceSignals({
    question: '北京大学宿舍和食堂体验怎么样',
    recommendedMajors: [],
    interests: [],
    count: 5,
  }, database as never);
  expect(result.items).toHaveLength(2);
  expect(result.items[0]).toMatchObject({
    kind: 'experience_aggregate',
    url: '',
    presentation: {
      type: 'experience_aggregate',
      institutionName: '北京大学',
    },
  });
  expect(database.experienceSignalAggregate.findMany).toHaveBeenCalledWith(
    expect.objectContaining({
      where: expect.objectContaining({
        reviewStatus: 'approved',
        publishedAt: { not: null },
      }),
    }),
  );
});
```

- [ ] **Step 2: Run the backend test and confirm it fails**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceSignalSearch.test.ts
```

Expected: FAIL because experience aggregate search does not exist.

- [ ] **Step 3: Extend the source presentation contract**

```ts
export type UnifiedSourcePresentation =
  | { type: 'external_link' }
  | {
      type: 'experience_aggregate';
      institutionName: string;
      aspect: string;
      timeWindowLabel: string;
      platformLabels: string[];
      independentSourceCount: number;
      uniqueContentCount: number;
      confidence: number;
    };

export type UnifiedContentItem = {
  // existing fields remain unchanged
  presentation?: UnifiedSourcePresentation;
};
```

Existing source fetchers may omit `presentation`; the answer layer treats that
as `{ type: 'external_link' }`.

- [ ] **Step 4: Implement aggregate retrieval**

Map Chinese question terms to the seven aspects:

```ts
const ASPECT_QUERY_PATTERNS: Array<[ExperienceAspect, RegExp]> = [
  ['dormitory', /宿舍|住宿|寝室/u],
  ['canteen', /食堂|吃饭|餐厅|伙食/u],
  ['course_and_workload', /课程|作业|上课|学习压力|卷/u],
  ['career_and_employment', /就业|实习|升学|保研|工作/u],
  ['major_resources', /专业|院系|科研资源|导师/u],
  ['clubs_and_culture', /社团|校园文化|活动/u],
  ['school_overall', /北京大学|北大|学校|校园/u],
];
```

Query only the matched aspects and:

```ts
where: {
  institutionCode: 'peking-university',
  aspect: { in: matchedAspects },
  reviewStatus: 'approved',
  publishedAt: { not: null },
  OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
}
```

Build one synthetic source item per aggregate. The summary combines recurring
themes, minority views and the required wording “以下为已审核的学生体验样本汇总，
不代表全体学生”。 Set `url: ''`; do not expose evidence IDs or raw source URLs.

- [ ] **Step 5: Merge official search and experience search**

In `storedAnswer.ts`, run both searches:

```ts
const [official, experience] = await Promise.all([
  searchStoredContent(searchInput, database),
  searchPublishedExperienceSignals(searchInput, database),
]);
return mergeStoredSourceResults(official, experience);
```

In `unifiedAnswer.ts`:

- add provider trust `experience-signals: 10`, below official S1/S2 sources;
- tell the model that `experience_aggregate` is sampled experience, not fact;
- require official candidates for policy/admission facts when both kinds exist;
- preserve `presentation` in selected source output.

- [ ] **Step 6: Add Flutter parsing and source-card behavior**

Add:

```dart
/// 控制来源卡展示；体验聚合没有单条原文链接。
class UnifiedSourcePresentation {
  const UnifiedSourcePresentation({
    required this.type,
    required this.timeWindowLabel,
    required this.platformLabels,
    required this.uniqueContentCount,
    required this.confidence,
  });

  final String type;
  final String timeWindowLabel;
  final List<String> platformLabels;
  final int uniqueContentCount;
  final double confidence;

  bool get isExperienceAggregate => type == 'experience_aggregate';
}
```

For experience aggregate cards:

- title badge: `学生体验汇总`;
- show time window, platform labels, sample count and confidence;
- show “不代表全体学生”的 explanation;
- do not render “复制链接”;
- retain the current link button for official/external sources.

- [ ] **Step 7: Add Flutter widget assertions**

```dart
testWidgets('experience aggregate source hides raw link action', (tester) async {
  await pumpAnswerWithSource(
    tester,
    kind: 'experience_aggregate',
    presentation: {
      'type': 'experience_aggregate',
      'timeWindowLabel': '2022–2026',
      'platformLabels': ['知乎', '贴吧'],
      'uniqueContentCount': 18,
      'confidence': 7.6,
    },
  );
  expect(find.text('学生体验汇总'), findsOneWidget);
  expect(find.textContaining('不代表全体学生'), findsOneWidget);
  expect(find.text('复制链接'), findsNothing);
});
```

- [ ] **Step 8: Run backend and Flutter tests**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceSignalSearch.test.ts tests/unit/unifiedAnswer.test.ts
Set-Location ..
flutter test test/widget_test.dart
dart analyze lib/main.dart lib/unified_content_answer_test.dart test/widget_test.dart
```

Expected: all commands PASS.

- [ ] **Step 9: Commit the App integration task**

```powershell
git add .backend_patch/lib/experience-signals/search.ts .backend_patch/lib/content-library/storedAnswer.ts .backend_patch/lib/content-sources .backend_patch/tests/unit/experienceSignalSearch.test.ts .backend_patch/tests/unit/unifiedAnswer.test.ts lib/unified_content_answer_test.dart test/widget_test.dart
git commit -m "feat: answer with reviewed experience aggregates"
```

---

### Task 11: Add retention cleanup and end-to-end acceptance

**Files:**
- Create: `.backend_patch/lib/experience-signals/retention.ts`
- Create: `.backend_patch/scripts/cleanup-expired-experience-raw.ts`
- Create: `.backend_patch/tests/unit/experienceRetention.test.ts`
- Create: `.backend_patch/tests/unit/experienceSignalFlow.test.ts`
- Modify: `.backend_patch/package.json`
- Modify: `deploy/uniprism-community-evidence-pilot/deploy.sh`
- Modify: `deploy/uniprism-community-evidence-pilot/README.md`
- Modify: `deploy/uniprism-community-evidence-pilot/systemd/uniprism-community-evidence.timer`

**Interfaces:**
- Consumes: all earlier tasks.
- Produces:
  - `deleteExpiredExperienceRaw(database, now)`
  - `npm run experience:cleanup-raw`
  - verified deployment bundle with community timer disabled.

- [ ] **Step 1: Write the failing retention test**

```ts
it('clears only expired ciphertext and records an audit row', async () => {
  const result = await deleteExpiredExperienceRaw(
    database as never,
    new Date('2026-08-31T00:00:00Z'),
  );
  expect(result.deletedCount).toBe(2);
  expect(transaction.experienceRawSample.updateMany).toHaveBeenCalledWith({
    where: {
      retentionUntil: { lte: new Date('2026-08-31T00:00:00Z') },
      processingStatus: { not: 'deleted' },
    },
    data: {
      encryptedRawText: null,
      rawTextIv: null,
      rawTextAuthTag: null,
      encryptionKeyVersion: null,
      sanitizedText: null,
      processingStatus: 'deleted',
    },
  });
  expect(transaction.auditLog.create).toHaveBeenCalledWith(
    expect.objectContaining({
      data: expect.objectContaining({
        action: 'experience_raw.retention_delete',
      }),
    }),
  );
});
```

- [ ] **Step 2: Write the failing vertical-flow test**

The test must simulate:

```ts
// source approved
// -> one useful sample + one spam sample
// -> useful sample becomes pending evidence
// -> admin approves evidence
// -> recompute creates pending aggregate
// -> admin approves aggregate
// -> App search returns aggregate only
// -> spam and pending aggregate never reach App
```

Assertions:

```ts
expect(flow.rawSamples).toBe(2);
expect(flow.approvedEvidence).toBe(1);
expect(flow.publishedAggregates).toBe(1);
expect(flow.appItems).toHaveLength(1);
expect(JSON.stringify(flow.appItems)).not.toContain('13800138000');
expect(JSON.stringify(flow.appItems)).not.toContain('encryptedRawText');
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run:

```powershell
Set-Location .backend_patch
npm test -- --run tests/unit/experienceRetention.test.ts tests/unit/experienceSignalFlow.test.ts
```

Expected: FAIL because retention cleanup and the integrated flow are incomplete.

- [ ] **Step 4: Implement scoped retention cleanup**

```ts
export async function deleteExpiredExperienceRaw(
  database: ExperienceRetentionDatabase,
  now = new Date(),
) {
  return database.$transaction(async (transaction) => {
    const deleted = await transaction.experienceRawSample.updateMany({
      where: {
        retentionUntil: { lte: now },
        processingStatus: { not: 'deleted' },
      },
      data: {
        encryptedRawText: null,
        rawTextIv: null,
        rawTextAuthTag: null,
        encryptionKeyVersion: null,
        sanitizedText: null,
        processingStatus: 'deleted',
      },
    });
    await transaction.auditLog.create({
      data: {
        actorUserId: null,
        action: 'experience_raw.retention_delete',
        resourceType: 'experience_raw_sample_batch',
        resourceId: now.toISOString(),
        metadata: { deletedCount: deleted.count, executedAt: now.toISOString() },
      },
    });
    return { deletedCount: deleted.count };
  });
}
```

Add:

```json
"experience:cleanup-raw": "tsx scripts/cleanup-expired-experience-raw.ts"
```

The script must never print raw text or encryption material.

- [ ] **Step 5: Update deployment behavior**

Deployment must:

- back up the new schema, experience modules, routes and worker;
- run `prisma migrate deploy`, `db:generate`, focused tests and `npm run build`;
- restart only `UniPrism_New` and the existing community analysis worker;
- install but `disable --now` the ECS community timer;
- not configure or expose local CDP on ECS;
- print the admin review URL and local runbook path;
- retain the current rollback directory behavior.

The timer file may keep a future 3–6 month example schedule, but deployment must
leave it disabled. Do not schedule community collection daily.

- [ ] **Step 6: Run all relevant verification**

Backend:

```powershell
Set-Location .backend_patch
npx prisma validate
npm run db:generate
npm test -- --run
npm run typecheck
npm run build
```

Crawler:

```powershell
Set-Location ..\.crawler_scaffold\university-crawler
.\.venv\Scripts\python.exe -m pytest -q
```

Flutter:

```powershell
Set-Location ..\..
flutter test
dart analyze lib/main.dart lib/unified_content_answer_test.dart test
```

Expected: all new tests PASS. If an unrelated pre-existing failure remains,
record its exact command and output separately; do not report it as caused by
this feature.

- [ ] **Step 7: Perform the manual Beijing University acceptance**

1. Approve Zhihu and Tieba source policies in the admin source-governance tab.
2. Launch the dedicated Chrome and log in manually.
3. Confirm `Test-NetConnection 127.0.0.1 -Port 9222` is true.
4. Run:

```powershell
.\tool\run_experience_snapshot.ps1 -Platform all -Dimension all
```

5. Confirm Chrome remains open after the Agent exits.
6. Confirm the admin run tab reports the real `completed / partial / blocked`
   state and no run is mislabeled.
7. Review the first evidence sample set.
8. Recompute and review all seven aggregate dimensions.
9. Ask the App “北京大学宿舍、食堂和课程体验怎么样？”
10. Confirm the answer separates official facts and student experience,
    displays an aggregate card, shows no commenter identity and offers no raw
    link button.

- [ ] **Step 8: Commit retention and deployment**

```powershell
git add .backend_patch/lib/experience-signals/retention.ts .backend_patch/scripts/cleanup-expired-experience-raw.ts .backend_patch/tests/unit/experienceRetention.test.ts .backend_patch/tests/unit/experienceSignalFlow.test.ts .backend_patch/package.json deploy/uniprism-community-evidence-pilot docs/operations/experience-snapshot-runbook.md
git commit -m "chore: finalize experience signal operations"
```

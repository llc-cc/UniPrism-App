# Beijing University Community Evidence Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Beijing University pilot that discovers public Zhihu and Baidu Tieba links, extracts directly visible public text, removes junk and personal data, stores traceable evidence in the cloud database, and exposes every accepted candidate in the existing admin review center.

**Architecture:** Extend the existing Python Playwright crawler with a licensed search-provider adapter and two isolated platform extractors. Send bounded batches to a new authenticated Next.js ingestion route; the backend performs deterministic cleaning, idempotent persistence and asynchronous AI analysis before administrators review the evidence. This first plan stops at “cleaned evidence available for review”; opinion aggregation and App retrieval are a separate follow-up plan after the first data quality review.

**Tech Stack:** Python 3.11, Playwright, httpx, BeautifulSoup, pytest, Next.js 16, TypeScript, Zod, Prisma 5/MySQL, Redis/BullMQ, DeepSeek JSON API, Vitest.

## Global Constraints

- First scope is exactly Beijing University, Zhihu, Baidu Tieba, and the seven dimensions: school, major, course, employment, dormitory, cafeteria, and student club.
- Only anonymous public pages may be visited; no account cookies, login automation, CAPTCHA solving, IP hiding/rotation, stealth plug-ins, private APIs, or access-control bypasses.
- A blocked, login-only, CAPTCHA, robots-disallowed, or 403 page is recorded and skipped.
- Raw account identifiers, nicknames, avatars, profile URLs, phone numbers, WeChat, QQ, email addresses and QR-code content must not be persisted.
- First-batch evidence is always `human_required`; no evidence may participate in App answers before explicit admin approval.
- Do not modify invitation-code management or unrelated admin pages. Extend only `/admin/content-ingestion`.
- New modules, asynchronous state transitions, privacy branches and review decisions require concise Chinese comments explaining why and boundary conditions.
- Follow `docs/DEVELOPMENT_CODE_STANDARD.md`.
- Backend changes require focused Vitest coverage; crawler changes require pytest coverage; production handoff requires Prisma validation, relevant tests and `npm run build`.
- Automated discovery uses the official Brave Search API endpoint and the `BRAVE_SEARCH_API_KEY` environment variable. Missing credentials must produce a visible `DISCOVERY_NOT_CONFIGURED` state, never a fake successful run.

---

### Task 1: Add Community Evidence Persistence Schema

**Files:**
- Modify: `.backend_patch/prisma/schema.prisma`
- Modify: `.backend_patch/prisma/content-ingestion-schema.prisma`
- Create: `.backend_patch/prisma/migrations/20260731_community_evidence_pilot/migration.sql`
- Test: `.backend_patch/tests/unit/communityEvidenceSchema.test.ts`

**Interfaces:**
- Consumes: existing `ContentItem`, `ContentIngestionBatch`, `ContentReviewStatus`, `ContentLifecycleStatus`.
- Produces: Prisma model `CommunityEvidenceAnalysis`; nullable `ContentIngestionBatch.stageMetrics`; relation `ContentItem.communityEvidenceAnalysis`.

- [ ] **Step 1: Write the failing schema contract test**

```ts
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('community evidence Prisma schema', () => {
  const schema = readFileSync('.backend_patch/prisma/schema.prisma', 'utf8');

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
    expect(schema).toMatch(/model ContentIngestionBatch[\s\S]*stageMetrics\s+Json\?/);
  });
});
```

- [ ] **Step 2: Run the schema test and verify it fails**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityEvidenceSchema.test.ts
```

Expected: FAIL because `CommunityEvidenceAnalysis` and `stageMetrics` do not exist.

- [ ] **Step 3: Add the model and migration**

Add a focused analysis model with these fields:

```prisma
model CommunityEvidenceAnalysis {
  id                 String   @id @default(cuid())
  contentItemId      String   @unique
  institutionCode    String   @db.VarChar(80)
  institutionName    String   @db.VarChar(160)
  majorName          String?  @db.VarChar(160)
  platform           String   @db.VarChar(40)
  dimension          String   @db.VarChar(40)
  qualityScore       Int
  credibilityScore  Decimal? @db.Decimal(4, 2)
  similarityHash     String   @db.Char(16)
  duplicateClusterId String?  @db.VarChar(191)
  spamSignals        Json?
  privacyFlags       Json?
  sentiment          Json?
  claims             Json?
  analysisStatus     String   @default("rules_passed") @db.VarChar(40)
  model              String?  @db.VarChar(120)
  promptVersion      String?  @db.VarChar(80)
  reviewerUserId     String?  @db.VarChar(191)
  reviewedAt         DateTime?
  reviewNote         String?  @db.Text
  createdAt          DateTime @default(now())
  updatedAt          DateTime @updatedAt

  contentItem ContentItem @relation(fields: [contentItemId], references: [id], onDelete: Cascade)

  @@index([institutionCode, dimension, analysisStatus])
  @@index([platform, createdAt])
  @@index([duplicateClusterId])
  @@map("community_evidence_analyses")
}
```

Add `stageMetrics Json?` to `ContentIngestionBatch` and the one-to-one relation to `ContentItem`. The migration must add only nullable columns/new tables and matching indexes so existing production records remain valid.

- [ ] **Step 4: Validate and retest**

Run:

```powershell
npx prisma validate --schema .backend_patch/prisma/schema.prisma
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityEvidenceSchema.test.ts
```

Expected: Prisma schema valid; test PASS.

- [ ] **Step 5: Commit**

```powershell
git add .backend_patch/prisma .backend_patch/tests/unit/communityEvidenceSchema.test.ts
git commit -m "feat(content): add community evidence schema"
```

---

### Task 2: Implement Deterministic Comment Cleaning and Similarity Signals

**Files:**
- Create: `.backend_patch/lib/content-ingestion/communityContracts.ts`
- Create: `.backend_patch/lib/content-ingestion/communityCleaner.ts`
- Create: `.backend_patch/lib/content-ingestion/communitySimilarity.ts`
- Test: `.backend_patch/tests/unit/communityCleaner.test.ts`
- Test: `.backend_patch/tests/unit/communitySimilarity.test.ts`

**Interfaces:**
- Produces: `cleanCommunityEvidence(input: CommunityEvidenceInput): CommunityCleaningResult`.
- Produces: `computeSimilarityHash(text: string): string` and `isNearDuplicate(left: string, right: string, maxDistance?: number): boolean`.
- `CommunityCleaningResult` contains `decision`, `sanitizedText`, `qualityScore`, `spamSignals`, `privacyFlags`, `contentHash`, and `similarityHash`.

- [ ] **Step 1: Write failing cleaning tests**

```ts
it('rejects meaningless short reactions', () => {
  expect(cleanCommunityEvidence({ text: '哈哈哈哈', title: '北大', platform: 'zhihu' }).decision)
    .toBe('rejected');
});

it('redacts contact details and sends the candidate to review', () => {
  const result = cleanCommunityEvidence({
    text: '课程体验很好，想交流可以加微信 abc_123456',
    title: '北京大学课程',
    platform: 'tieba',
  });
  expect(result.sanitizedText).not.toContain('abc_123456');
  expect(result.privacyFlags).toContain('wechat_id');
  expect(result.decision).toBe('review_required');
});

it('does not reject a normal discussion merely because it mentions WeChat', () => {
  const result = cleanCommunityEvidence({
    text: '学校微信公众号会发布选课时间，建议开学后关注通知。',
    title: '北京大学选课',
    platform: 'zhihu',
  });
  expect(result.decision).not.toBe('rejected');
});
```

- [ ] **Step 2: Run the tests and verify missing-module failures**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityCleaner.test.ts .backend_patch/tests/unit/communitySimilarity.test.ts
```

Expected: FAIL because the cleaner and similarity modules do not exist.

- [ ] **Step 3: Implement minimal rules**

Implement:

- NFKC/whitespace/punctuation normalization;
- phone, email, WeChat, QQ and profile-link redaction;
- solicitation scoring that requires at least two advertising signals before hard rejection;
- repeated-character, emoji-only, punctuation-only and low-information rejection;
- SHA-256 content hash;
- dependency-free 64-bit SimHash over Chinese bigrams and Latin tokens;
- quality score clamped to `0..100`;
- all non-rejected first-batch records return `review_required`.

Do not call AI in this module.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityCleaner.test.ts .backend_patch/tests/unit/communitySimilarity.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .backend_patch/lib/content-ingestion/community*.ts .backend_patch/tests/unit/community*.test.ts
git commit -m "feat(content): clean and fingerprint community evidence"
```

---

### Task 3: Add Authenticated Community Evidence Ingestion

**Files:**
- Create: `.backend_patch/lib/content-ingestion/communitySources.ts`
- Create: `.backend_patch/lib/content-ingestion/communityIngestion.ts`
- Create: `.backend_patch/app/api/internal/content-ingestion/community/route.ts`
- Modify: `.backend_patch/lib/content-ingestion/repository.ts`
- Test: `.backend_patch/tests/unit/communityIngestion.test.ts`
- Test: `.backend_patch/tests/unit/contentRepositoryReview.test.ts`

**Interfaces:**
- Consumes: `cleanCommunityEvidence`, `persistNormalizedContent`, existing bearer-token authorization.
- Produces: `communityIngestionPayloadSchema`.
- Produces: `ingestCommunityEvidence(prisma, payload): Promise<CommunityIngestionResult>`.
- Extends `PersistNormalizedContentInput` with optional `forceHumanReview?: boolean`.

- [ ] **Step 1: Write failing ingestion tests**

Cover:

```ts
it('accepts only the Beijing University pilot and supported platforms', () => {
  expect(() => communityIngestionPayloadSchema.parse(validPayload)).not.toThrow();
  expect(() => communityIngestionPayloadSchema.parse({
    ...validPayload,
    institutionCode: 'tsinghua-university',
  })).toThrow();
  expect(() => communityIngestionPayloadSchema.parse({
    ...validPayload,
    platform: 'xiaohongshu',
  })).toThrow();
});

it('forces every stored community item into human review', async () => {
  const result = await persistNormalizedContent(database, {
    ...input,
    forceHumanReview: true,
  });
  expect(database.contentItem.create).toHaveBeenCalledWith(expect.objectContaining({
    data: expect.objectContaining({
      reviewStatus: 'human_required',
      lifecycleStatus: 'review_required',
    }),
  }));
});
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityIngestion.test.ts .backend_patch/tests/unit/contentRepositoryReview.test.ts
```

Expected: FAIL because the API contract and forced-review branch do not exist.

- [ ] **Step 3: Implement the source registry and ingestion flow**

Register only:

```ts
export const COMMUNITY_SOURCE_DEFINITIONS = {
  zhihu: {
    code: 'zhihu-peking-university-public',
    allowedHosts: ['zhihu.com', 'www.zhihu.com', 'zhuanlan.zhihu.com'],
  },
  tieba: {
    code: 'tieba-peking-university-public',
    allowedHosts: ['tieba.baidu.com'],
  },
} as const;
```

For both sources:

- `allowStoreRawSnapshot = false`;
- `allowStoreBody = true` only after deterministic redaction;
- `allowAiProcess = true`;
- `allowRecommend = false`;
- `allowPush = false`;
- source status starts `paused` until the first manual run is approved.

The ingestion route must:

1. authorize the crawler token;
2. validate institution/platform/dimension/host and a maximum 50 comments per request;
3. clean every candidate;
4. count rejected records without storing rejected body text;
5. persist reviewable evidence with `forceHumanReview: true`;
6. create/update `CommunityEvidenceAnalysis`;
7. write stage counts into `ContentIngestionBatch.stageMetrics`;
8. return created, updated, unchanged, rejected and failed counts.

- [ ] **Step 4: Run the tests**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityIngestion.test.ts .backend_patch/tests/unit/contentRepositoryReview.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .backend_patch/lib/content-ingestion .backend_patch/app/api/internal/content-ingestion/community .backend_patch/tests/unit
git commit -m "feat(content): ingest reviewable community evidence"
```

---

### Task 4: Add Licensed Search Discovery and Platform Policy Gate

**Files:**
- Modify: `.crawler_scaffold/university-crawler/pyproject.toml`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/config.py`
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_models.py`
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_discovery.py`
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_policies.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_discovery.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_policies.py`

**Interfaces:**
- Produces: `discover_public_links(plan, settings) -> list[DiscoveredLink]`.
- Produces: `evaluate_public_url(url, platform) -> PolicyDecision`.
- `PolicyDecision` is one of `allowed`, `blocked_host`, `blocked_path`, `unsupported_platform`.

- [ ] **Step 1: Write failing discovery tests**

Use `httpx.MockTransport` to assert:

```python
async def test_discovery_uses_site_limited_queries_and_deduplicates():
    links = await discover_public_links(
        CommunityDiscoveryPlan(
            institution_code="peking-university",
            institution_name="北京大学",
            platforms=["zhihu", "tieba"],
            dimensions=["course", "dormitory"],
        ),
        settings,
        transport=mock_transport,
    )
    assert {link.platform for link in links} == {"zhihu", "tieba"}
    assert len({str(link.url) for link in links}) == len(links)
```

Also assert missing `BRAVE_SEARCH_API_KEY` raises a typed `DiscoveryNotConfigured` error before any HTTP request.

- [ ] **Step 2: Run pytest and verify failures**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_discovery.py .crawler_scaffold/university-crawler/tests/test_community_policies.py -q
```

Expected: FAIL because discovery modules do not exist.

- [ ] **Step 3: Implement the discovery adapter**

Use:

```text
GET https://api.search.brave.com/res/v1/web/search
Header: X-Subscription-Token: ${BRAVE_SEARCH_API_KEY}
```

Generate bounded queries from the seven approved dimensions and explicit `site:` filters. Limit each query to ten results, cap one run at 140 unique URLs, reject non-HTTPS URLs and hosts outside the platform registry, and persist no search response body.

Add settings:

```python
brave_search_api_key: str = ""
community_discovery_max_results: int = Field(default=140, ge=1, le=500)
community_request_delay_seconds: float = Field(default=3.0, ge=1.0, le=30.0)
```

- [ ] **Step 4: Run pytest**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_discovery.py .crawler_scaffold/university-crawler/tests/test_community_policies.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .crawler_scaffold/university-crawler
git commit -m "feat(crawler): discover approved community links"
```

---

### Task 5: Extract Only Directly Visible Public Zhihu and Tieba Text

**Files:**
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_extractors.py`
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_crawler.py`
- Create: `.crawler_scaffold/university-crawler/tests/fixtures/zhihu_public_page.html`
- Create: `.crawler_scaffold/university-crawler/tests/fixtures/tieba_public_page.html`
- Create: `.crawler_scaffold/university-crawler/tests/fixtures/login_wall.html`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_extractors.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_crawler.py`

**Interfaces:**
- Produces: `extract_public_evidence(platform, html, page_url) -> list[CommunityEvidenceCandidate]`.
- Produces: `crawl_discovered_link(link, settings) -> CommunityCrawlResult`.
- `CommunityCrawlResult` has `status`, `candidates`, `block_reason`, `final_url`, and `elapsed_ms`.

- [ ] **Step 1: Add sanitized HTML fixtures and failing tests**

Fixtures must contain invented text, not copied production comments. Test that:

- title/post body/directly visible comments are extracted;
- usernames, avatar URLs and profile links are not emitted;
- login wall returns `blocked_login`;
- CAPTCHA text returns `blocked_captcha`;
- a redirect outside the allowed host returns `blocked_redirect`;
- no extractor calls hidden JSON/private API endpoints.

- [ ] **Step 2: Run pytest and verify failures**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_extractors.py .crawler_scaffold/university-crawler/tests/test_community_crawler.py -q
```

Expected: FAIL because crawler modules do not exist.

- [ ] **Step 3: Implement bounded Playwright collection**

The crawler must:

- create a fresh anonymous browser context without stored cookies;
- set a truthful UniPrism crawler user agent and contact placeholder configured by environment;
- navigate only to policy-approved URLs;
- wait at most 20 seconds for DOM-ready plus 5 seconds for bounded rendering;
- inspect only rendered HTML;
- avoid clicking login, “load all comments”, follow, like or other interactive controls;
- cap each page at 100 directly visible evidence candidates;
- close the context after each platform batch;
- return a typed blocked result instead of retrying access controls.

- [ ] **Step 4: Run pytest**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_extractors.py .crawler_scaffold/university-crawler/tests/test_community_crawler.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .crawler_scaffold/university-crawler/src .crawler_scaffold/university-crawler/tests
git commit -m "feat(crawler): extract public community evidence"
```

---

### Task 6: Stream Community Evidence to the Existing Cloud Backend

**Files:**
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/ingestion.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/main.py`
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_runner.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_ingestion.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_runner.py`
- Modify: `.crawler_scaffold/university-crawler/.env.example`
- Modify: `.crawler_scaffold/university-crawler/README.md`

**Interfaces:**
- Produces: `upload_community_evidence(batch, settings)`.
- Produces CLI:

```text
python -m university_crawler.main --community --institution peking-university --platform all
```

- [ ] **Step 1: Write failing upload and orchestration tests**

Test:

- batches contain at most 50 candidates;
- retries happen only for network errors and 5xx responses, maximum three attempts;
- 401/403 from the UniPrism backend fails immediately;
- discovery-not-configured returns exit code 4;
- platform blocks are counted and execution continues with the other platform;
- no crawler result is written to local disk.

- [ ] **Step 2: Run pytest and verify failures**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_ingestion.py .crawler_scaffold/university-crawler/tests/test_community_runner.py -q
```

Expected: FAIL before implementation.

- [ ] **Step 3: Implement the runner and CLI**

The runner must expose stage counts:

```python
{
    "discovered": 0,
    "allowed": 0,
    "blocked": 0,
    "pages_fetched": 0,
    "candidates_extracted": 0,
    "uploaded": 0,
    "rejected": 0,
    "failed": 0,
}
```

Add environment documentation for `BRAVE_SEARCH_API_KEY` and `CRAWLER_COMMUNITY_INGEST_URL`. Do not place real credentials in source control.

- [ ] **Step 4: Run the complete Python suite**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests -q
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add .crawler_scaffold/university-crawler
git commit -m "feat(crawler): run Beijing community evidence pilot"
```

---

### Task 7: Analyze Sanitized Evidence Asynchronously

**Files:**
- Create: `.backend_patch/lib/community-analysis/contracts.ts`
- Create: `.backend_patch/lib/community-analysis/analyzer.ts`
- Create: `.backend_patch/lib/community-analysis/queue.ts`
- Create: `.backend_patch/scripts/workers/community-evidence-analysis-worker.ts`
- Test: `.backend_patch/tests/unit/communityEvidenceAnalyzer.test.ts`
- Test: `.backend_patch/tests/unit/communityEvidenceQueue.test.ts`

**Interfaces:**
- Consumes: sanitized `ContentDocument.bodyText` and `CommunityEvidenceAnalysis`.
- Produces: `analyzeCommunityEvidence(input, aiCall)`.
- Produces BullMQ job name `community-evidence-analysis` keyed by `contentItemId:cleanerVersion`.

- [ ] **Step 1: Write failing analyzer tests**

Require strict JSON:

```ts
{
  institutionCode: 'peking-university',
  majorName: null,
  dimension: 'course',
  claim: '课程节奏较快',
  sentiment: { course: 'mixed' },
  informationValue: 8,
  credibility: 6.5,
  riskReasons: [],
  requiresHumanReview: true
}
```

Test invalid dimensions, scores outside range, markdown-wrapped JSON, timeout, and the rule that AI never changes `reviewStatus` to approved.

- [ ] **Step 2: Run the tests and verify failures**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityEvidenceAnalyzer.test.ts .backend_patch/tests/unit/communityEvidenceQueue.test.ts
```

Expected: FAIL because analyzer and queue do not exist.

- [ ] **Step 3: Implement analyzer and idempotent queue**

Use existing `callDeepSeekJson` with:

- `DEEPSEEK_COMMUNITY_ANALYSIS_MODEL`;
- temperature `0`;
- timeout `12_000ms`;
- maximum 500 output tokens;
- prompt version `community-evidence-v1`.

The worker updates only analysis fields. Failure sets `analysisStatus = ai_failed` and retains the item in human review. Logs must contain content item ID and error code, never the evidence body.

- [ ] **Step 4: Run tests**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityEvidenceAnalyzer.test.ts .backend_patch/tests/unit/communityEvidenceQueue.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .backend_patch/lib/community-analysis .backend_patch/scripts/workers .backend_patch/tests/unit
git commit -m "feat(content): analyze community evidence asynchronously"
```

---

### Task 8: Add Admin Review APIs and Audit Trail

**Files:**
- Create: `.backend_patch/lib/adminCommunityEvidence.ts`
- Create: `.backend_patch/app/api/admin/content-ingestion/community-evidence/route.ts`
- Create: `.backend_patch/app/api/admin/content-ingestion/community-evidence/[itemId]/route.ts`
- Test: `.backend_patch/tests/unit/adminCommunityEvidence.test.ts`
- Test: `.backend_patch/tests/unit/adminCommunityEvidenceContracts.test.ts`

**Interfaces:**
- Produces: paginated GET filters for `status`, `platform`, `dimension`, `query`, `page`.
- Produces: PATCH actions `approve`, `reject`, `edit_and_approve`.
- Uses existing `AuditLog` for immutable review audit records.

- [ ] **Step 1: Write failing review tests**

Test that:

- only admin sessions can list or review evidence;
- list response never includes usernames, account IDs, avatars or raw snapshots;
- approving sets `ContentItem.reviewStatus = approved` and `lifecycleStatus = approved`;
- rejecting sets both statuses to rejected;
- editing stores the sanitized edited text as a new content version;
- every action creates an `AuditLog` record;
- a second review request with the stale `updatedAt` returns conflict instead of overwriting another reviewer.

- [ ] **Step 2: Run focused tests**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/adminCommunityEvidence.test.ts .backend_patch/tests/unit/adminCommunityEvidenceContracts.test.ts
```

Expected: FAIL before implementation.

- [ ] **Step 3: Implement list and mutation services**

Keep database reads, review decisions and HTTP response mapping in separate functions. Use Zod for all query and PATCH payloads. `edit_and_approve` must rerun deterministic cleaning before saving.

- [ ] **Step 4: Run tests**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/adminCommunityEvidence.test.ts .backend_patch/tests/unit/adminCommunityEvidenceContracts.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .backend_patch/lib/adminCommunityEvidence.ts .backend_patch/app/api/admin/content-ingestion/community-evidence .backend_patch/tests/unit
git commit -m "feat(admin): review community evidence"
```

---

### Task 9: Add the Community Review Tab to the Existing Monitor

**Files:**
- Create: `.backend_patch/app/admin/content-ingestion/CommunityEvidenceReviewClient.tsx`
- Create: `.backend_patch/app/admin/content-ingestion/community-evidence/page.tsx`
- Modify: `.backend_patch/app/admin/content-ingestion/AdminContentIngestionDashboardClient.tsx`
- Test: `.backend_patch/tests/unit/communityEvidenceAdminPage.test.tsx`

**Interfaces:**
- Consumes: admin community-evidence APIs from Task 8.
- Produces: navigation entry and review table under `/admin/content-ingestion/community-evidence`.

- [ ] **Step 1: Write the failing UI behavior test**

Test:

- content monitor includes “内容审核” without changing links to other admin modules;
- page defaults to pending/human-required evidence;
- filters cover platform and seven dimensions;
- approve/reject/edit buttons show loading, success and error states;
- source link opens in a new tab with `rel="noreferrer"`;
- no raw account identity fields are rendered;
- pagination does not fetch more than 20 records per page.

- [ ] **Step 2: Run the test and verify failure**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityEvidenceAdminPage.test.tsx
```

Expected: FAIL because the review page does not exist.

- [ ] **Step 3: Implement the review interface**

Display:

- school, platform, dimension;
- sanitized evidence;
- AI claim, information value, credibility and risk;
- duplicate cluster count;
- public source URL and collection time;
- approve, reject and edit-and-approve actions.

Do not add community controls to invitation management or unrelated pages.

- [ ] **Step 4: Run the test**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit/communityEvidenceAdminPage.test.tsx
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add .backend_patch/app/admin/content-ingestion .backend_patch/tests/unit/communityEvidenceAdminPage.test.tsx
git commit -m "feat(admin): add community evidence review page"
```

---

### Task 10: Verify, Deploy and Collect the First Review Batch

**Files:**
- Modify: `deploy/README.md`
- Create: `deploy/uniprism-community-evidence-pilot/`
- Create: `deploy/uniprism-community-evidence-pilot/deploy.sh`
- Create: `deploy/uniprism-community-evidence-pilot/systemd/uniprism-community-evidence.service`
- Create: `deploy/uniprism-community-evidence-pilot/systemd/uniprism-community-evidence.timer`

**Interfaces:**
- Consumes all preceding tasks.
- Produces a disabled-by-default ECS timer and one manual Beijing University pilot run.

- [ ] **Step 1: Run all local verification**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests -q
npx vitest --config vitest.backend-patch.config.ts run
npx prisma validate --schema .backend_patch/prisma/schema.prisma
```

Expected: all PASS.

- [ ] **Step 2: Copy the staged backend files into the canonical backend and verify production build**

Copy only files named by this plan into `D:\ywkeji\Uniprism\UniPrism_New-main`, preserving unrelated work. Then run:

```powershell
npm run db:generate
npm run build
```

Expected: Prisma generation and Next.js production build PASS.

- [ ] **Step 3: Create a recoverable ECS deployment bundle**

The deployment script must:

- verify expected backend and crawler paths before changing anything;
- create a timestamped backup;
- apply `prisma migrate deploy`;
- install the crawler package without deleting the current environment;
- add the AI worker to PM2;
- install a separate community timer in disabled state;
- restart only `UniPrism_New` and the new community worker;
- run HTTP and database read-only health checks;
- print the backup path and rollback commands.

- [ ] **Step 4: Configure discovery and run one manual pilot**

Required ECS environment-variable names (their values are configured directly
on ECS and never written into this repository):

```text
BRAVE_SEARCH_API_KEY
CRAWLER_COMMUNITY_INGEST_URL=http://127.0.0.1:3000/api/internal/content-ingestion/community
DEEPSEEK_COMMUNITY_ANALYSIS_MODEL
```

Run:

```bash
runuser -u uniprism-crawler -- \
  /opt/uniprism-crawler/venv/bin/python -m university_crawler.main \
  --community --institution peking-university --platform all
```

Expected:

- both platforms have discovered/allowed/blocked counts;
- directly visible public evidence is streamed to the backend;
- blocked pages remain recorded without bypass attempts;
- accepted evidence appears in the admin pending-review list;
- database items remain `allowRecommend = false`.

- [ ] **Step 5: Verify the first cloud batch**

Confirm with read-only queries:

```sql
SELECT
  cs.displayName,
  cib.status,
  cib.fetchedCount,
  cib.createdCount,
  cib.unchangedCount,
  cib.rejectedCount,
  cib.failedCount,
  cib.stageMetrics,
  cib.completedAt
FROM content_ingestion_batches cib
JOIN content_sources cs ON cs.id = cib.sourceId
WHERE cs.code IN (
  'zhihu-peking-university-public',
  'tieba-peking-university-public'
)
ORDER BY cib.createdAt DESC
LIMIT 20;
```

Also verify every first-batch item is `human_required/review_required` and has no persisted account identity.

- [ ] **Step 6: Keep community automation disabled and hand off review**

Do not enable the community timer until the user reviews the first batch in the admin center. Record:

- discovered, blocked, extracted, rejected, stored and AI-analyzed counts;
- at least ten representative accepted/rejected examples;
- cleaning false positives and false negatives;
- platform-specific parsing failures.

- [ ] **Step 7: Commit deployment assets and documentation**

```powershell
git add deploy docs
git commit -m "docs: add community evidence pilot deployment"
```

---

## Explicit Follow-up Plan

After the user reviews the first batch, create a separate implementation plan for:

- semantic embedding clusters at database scale;
- `community_opinion_aggregates`;
- school/profession confidence intervals and disagreement display;
- approved aggregate retrieval in the App;
- high-quality automatic approval thresholds;
- adding more schools and later platforms.

This separation prevents unreviewed community content from reaching users before the evidence quality is known.

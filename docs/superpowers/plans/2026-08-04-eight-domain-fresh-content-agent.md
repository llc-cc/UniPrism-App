# Eight-Domain Fresh Content Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing incremental official-page crawler from four universities to eight A-class content domains, ingest real detail-page bodies without repeating successful URLs, and deploy the verified crawler and minimal backend allowlist to ECS.

**Architecture:** Reuse the current Playwright crawler, upload cursor, authenticated browser-ingestion route, normalizer, repository, and systemd timer. Add eight bounded official/public sources to the existing registry and YAML, attach optional publication dates to documents, keep per-source URL/content hashes, and deploy only the changed crawler and source-registry code with a single controlled Webpack build.

**Tech Stack:** Python 3.11, Pydantic, BeautifulSoup, Playwright, pytest/unittest, Next.js 16, TypeScript, Zod, Prisma, Vitest, systemd

## Global Constraints

- Follow `docs/DEVELOPMENT_CODE_STANDARD.md`; add concise Chinese comments for source security boundaries, asynchronous state transitions, and deduplication decisions.
- Implement only eight A-class domains. Do not modify B-class community collection, login-browser behavior, or `ExperienceSignalAggregate`.
- Detail text is required. A listing excerpt must never be submitted as a detail body.
- Crawler state stores only source code, normalized URL, SHA-256 content hash, and upload time; it never stores page bodies.
- A cursor advances only after the backend accounts for every document with zero failures.
- Do not add a database migration or run a Turbopack build on ECS.
- Preserve all unrelated dirty-worktree changes and stage only files belonging to this feature.

---

### Task 1: Generalize the backend browser-source registry

**Files:**
- Modify: `.backend_patch/lib/content-ingestion/universityBrowserSources.ts`
- Modify: `.backend_patch/lib/content-ingestion/browserCrawl.ts`
- Modify: `.backend_patch/tests/unit/universityBrowserSources.test.ts`

**Interfaces:**
- Consumes: `getUniversityBrowserSource(sourceCode)` compatibility entry point.
- Produces: source definitions with `domainTag`, `sourceTag`, `sourceKind`, `allowedHosts`, `allowedCategories`, and rights policy; payload accepts optional `publishedAt`.

- [ ] **Step 1: Add failing tests for eight domains and publication time**

```ts
const expectedDomains = new Set([
  'education', 'public_data', 'news_trends', 'research_academic',
  'technology_open_source', 'product_industry', 'career_employment',
  'knowledge_culture_nature',
]);
expect(new Set(Object.values(UNIVERSITY_BROWSER_SOURCES).map((source) => source.domainTag)))
  .toEqual(expectedDomains);
expect(browserCrawlPayloadSchema.parse({
  sourceCode: 'xinhua-news',
  documents: [{ ...document, category: 'news_trends', url: 'https://www.news.cn/20260804/example.htm', publishedAt: '2026-08-04T01:00:00.000Z' }],
}).documents[0].publishedAt).toBe('2026-08-04T01:00:00.000Z');
```

- [ ] **Step 2: Run the focused Vitest and confirm it fails**

Run: `npm test -- --run tests/unit/universityBrowserSources.test.ts`

Expected: FAIL because generic domain fields and non-university definitions do not exist.

- [ ] **Step 3: Add the minimal generic fields and eight source definitions**

Keep the existing module path for compatibility, but define each source with explicit domain, attribution, source kind, hosts, category, and body policy. Register these codes: `ministry-education-news`, `national-statistics-releases`, `xinhua-news`, `arxiv-cs-recent`, `github-trending`, `miit-industry-analysis`, `mohrss-employment-policy`, and `wikipedia-featured-content`; the four existing universities share the education domain.

Update ingestion tags and source kind:

```ts
sourceKind: definition.sourceKind,
tags: ['fresh-content', definition.domainTag, definition.sourceTag, document.category],
publishedAt: document.publishedAt ?? null,
```

Add to `documentSchema`:

```ts
publishedAt: z.string().datetime().nullable().optional(),
```

- [ ] **Step 4: Run focused backend tests**

Run: `npm test -- --run tests/unit/universityBrowserSources.test.ts tests/unit/contentNormalizer.test.ts`

Expected: both files PASS.

---

### Task 2: Preserve publication dates in crawler documents

**Files:**
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/models.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/extractor.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/crawler.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/ingestion.py`
- Create: `.crawler_scaffold/university-crawler/tests/test_official_page_metadata.py`

**Interfaces:**
- Produces: `extract_published_at(html: str) -> datetime | None` and `CrawledDocument.published_at: datetime | None`.
- Upload JSON uses `publishedAt` as an ISO-8601 UTC string or `null`.

- [ ] **Step 1: Write failing metadata tests**

```python
def test_extracts_standard_article_published_time() -> None:
    html = '<meta property="article:published_time" content="2026-08-04T08:30:00+08:00"><article>正文</article>'
    assert extract_published_at(html).isoformat() == "2026-08-04T00:30:00+00:00"

def test_upload_payload_keeps_missing_date_null() -> None:
    assert _payload_document(_document(published_at=None))["publishedAt"] is None
```

- [ ] **Step 2: Run tests and confirm missing API failures**

Run: `python -m pytest tests/test_official_page_metadata.py -q`

Expected: FAIL because `extract_published_at` and `published_at` do not exist.

- [ ] **Step 3: Implement bounded metadata parsing**

Check `article:published_time`, `og:published_time`, `pubdate`, `publishdate`, `date`, and `<time datetime>`. Parse ISO-8601 values only, normalize naive dates to UTC, and return `None` for ambiguous free text. Add `published_at` to `CrawledDocument`, set it when a detail page is extracted, and serialize it in `_payload_document`.

- [ ] **Step 4: Run metadata and existing incremental tests**

Run: `python -m pytest tests/test_official_page_metadata.py tests/test_incremental_crawler.py tests/test_crawl_state.py -q`

Expected: PASS.

---

### Task 3: Configure the eight A-class domains

**Files:**
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/config.py`
- Modify: `.crawler_scaffold/university-crawler/sources.yaml`
- Create: `.crawler_scaffold/university-crawler/tests/test_eight_domain_sources.py`

**Interfaces:**
- Consumes: existing `SourceConfig` and `SeedPage` schema.
- Produces: enabled, allowlisted, bounded discovery entries for all eight domain category codes.

- [ ] **Step 1: Write a failing source-coverage test**

```python
def test_enabled_sources_cover_exactly_eight_a_domains() -> None:
    sources = [item for item in load_sources(Path("sources.yaml")) if item.enabled]
    domains = {source.domain for source in sources}
    assert {
        "education", "public_data", "news_trends", "research_academic",
        "technology_open_source", "product_industry", "career_employment",
        "knowledge_culture_nature",
    } == domains
    assert "community_experience" not in domains
```

- [ ] **Step 2: Run the coverage test and confirm it fails**

Run: `python -m pytest tests/test_eight_domain_sources.py -q`

Expected: FAIL because the YAML currently contains university-only category names.

- [ ] **Step 3: Add bounded source entries**

Add `domain: str = Field(pattern=r"^[a-z_]{3,64}$")` to `SourceConfig`. Keep the four university entries with `domain: education`, then add official/public list seeds for the codes from Task 1. Every list seed uses `discovery_only: true`, an explicit `follow_path_prefixes` or `follow_path_patterns`, and `max_pages: 10` for the first live run. Keep existing university detail categories while the source-level domain remains `education`; do not add any B-class host.

- [ ] **Step 4: Run configuration and incremental tests**

Run: `python -m pytest tests/test_eight_domain_sources.py tests/test_incremental_crawler.py tests/test_crawl_state.py -q`

Expected: PASS.

---

### Task 4: Verify the complete local change set

**Files:**
- Modify only if a focused failure exposes a feature defect in Tasks 1-3.

**Interfaces:**
- Produces: a test-verified backend source registry and crawler bundle.

- [ ] **Step 1: Run all crawler A-class tests**

Run: `python -m pytest tests/test_automation.py tests/test_scheduled_gate.py tests/test_crawl_state.py tests/test_incremental_crawler.py tests/test_official_page_metadata.py tests/test_eight_domain_sources.py -q`

Expected: PASS.

- [ ] **Step 2: Run backend ingestion tests**

Run: `npm test -- --run tests/unit/universityBrowserSources.test.ts tests/unit/contentNormalizer.test.ts`

Expected: PASS.

- [ ] **Step 3: Build once with Webpack outside ECS production execution**

Run: `npx next build --webpack`

Expected: build exits 0 without using Turbopack. If the local Windows artifact is not deployable to Linux, use this only as compilation verification and run the same single Webpack command in the ECS release directory during Task 6.

---

### Task 5: Run live source smoke tests and prove no repeat batch

**Files:**
- No source edits unless a live page has changed and the corresponding allowlisted path rule must be narrowed.

**Interfaces:**
- Consumes: production-like `.env`, `sources.yaml`, and isolated temporary cursor.
- Produces: one successful detail body per A-class domain and a second run with no repeated successful detail submissions.

- [ ] **Step 1: Run one source at a time with a temporary state path**

Set `CRAWLER_STATE_PATH` to a task-specific temporary file and invoke `python -m university_crawler.main --source <code>` for one source per domain. Do not print the ingest token.

Expected: each selected source reports at least one backend-accounted document with non-empty detail text.

- [ ] **Step 2: Run the same eight source commands again**

Expected: listing pages are refreshed, but already successful detail URLs are not uploaded again; source logs show zero repeated detail submissions.

- [ ] **Step 3: Inspect only aggregate ingestion results**

Confirm created/updated/unchanged/failed counts and body presence through the existing administrative/read-only inspection path. Do not print full bodies or credentials to logs.

---

### Task 6: Deploy and enable the ECS schedule

**Files:**
- Modify: `deploy/uniprism-university-automation-deploy/deploy.sh`
- Update: `deploy/uniprism-university-automation-deploy/crawler.tar.gz`
- Update: `deploy/uniprism-university-automation-deploy/backend.tar.gz`
- Update: `deploy/uniprism-university-automation-deploy.tar.gz`

**Interfaces:**
- Produces: ECS crawler with `/opt/uniprism-crawler/state/crawl-state.json`, generic backend allowlist, online main site, and enabled 03:00 timer.

- [ ] **Step 1: Make deployment crawler-state aware and time-bound**

The deployment script must back up exact target files, extract the new crawler and backend registry, create the writable state directory, set `CRAWLER_STATE_PATH`, run one `next build --webpack` attempt instead of `npm run build`, restart only `UniPrism_New` after a successful build, and leave the existing process untouched if the build fails.

- [ ] **Step 2: Rebuild archives from current verified files**

List archive contents and confirm `crawl_state.py`, all eight source codes, updated browser-source registry, and deployment script are present. Ensure the outer archive contains the newly generated inner archives rather than stale copies.

- [ ] **Step 3: Upload to a timestamped ECS release path and execute deployment**

Use the existing key `C:\Users\18165\.ssh\uniprism_deploy_ed25519`, port `22022`, and the already-authorized root account. Do not overwrite unrelated directories.

- [ ] **Step 4: Run one controlled ECS collection and one repeat run**

Expected first run: each enabled domain either uploads new/updated details or records a source-specific bounded failure. Expected second run: successful details from the first run are not submitted again.

- [ ] **Step 5: Verify service health**

Run read-only checks for `pm2` main-site status, HTTP readiness, `systemctl is-enabled`, `systemctl is-active`, `systemctl list-timers`, crawler state presence, and recent journal counts. The final report must distinguish successful domains from any blocked or layout-changed source.

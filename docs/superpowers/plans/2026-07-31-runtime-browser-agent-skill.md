# UniPrism Runtime Browser Agent + Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Beijing University community pilot's mandatory Brave discovery path with a DeepSeek-driven Browser Use runtime Agent that loads a repository-owned Skill, browses Zhihu and Tieba public pages, and submits validated evidence to the existing cleaning and human-review pipeline.

**Architecture:** Keep deterministic extraction and cloud ingestion as independent downstream modules. Add a Skill loader, a strict candidate collector, and a Browser Use adapter behind injected protocols so unit tests do not start a real browser or call DeepSeek. The runner executes fourteen platform/dimension tasks sequentially, merges their statistics, and uploads only validated, deduplicated candidates.

**Tech Stack:** Python 3.11, browser-use 0.12.x, Pydantic 2, DeepSeek, Chromium, pytest/unittest, Next.js 16, TypeScript, Zod, Prisma, Vitest, systemd.

## Global Constraints

- Reuse `DEEPSEEK_API_KEY`, optional `DEEPSEEK_BASE_URL`, and existing DeepSeek model configuration; never write secrets to source, logs, Skill text, or database.
- First scope is Beijing University, Zhihu and Tieba, and the seven dimensions `school`, `major`, `course`, `employment`, `dormitory`, `cafeteria`, `student_club`.
- Run platform/dimension tasks sequentially and keep browser concurrency at one on the current 3.5 GB server.
- A blocked or failed task must not stop later tasks.
- Do not implement CAPTCHA solving, login automation, private API access, proxy IP, fingerprint spoofing, or collection of account identities and contact details.
- All accepted evidence remains `human_required`; unreviewed evidence must not participate in App answers.
- Modify only crawler, content-ingestion backend, content-ingestion admin monitoring, tests, docs, and deployment assets.

---

### Task 1: Agent settings, task matrix, and Skill loader

**Files:**
- Create: `.crawler_scaffold/university-crawler/skills/uniprism-university-community-crawler/SKILL.md`
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_agent_skill.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/config.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_models.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_agent_skill.py`

**Interfaces:**
- Produces: `CommunityAgentTask`, `CommunityAgentTaskStatus`, `CommunityAgentTaskResult`.
- Produces: `load_community_agent_skill(path: Path) -> CommunityAgentSkill`.
- Produces: `build_community_agent_tasks(plan: CommunityDiscoveryPlan) -> list[CommunityAgentTask]`.
- Produces: `render_community_agent_task(skill, task, max_candidates) -> str`.

- [ ] **Step 1: Write failing Skill and task-matrix tests**

```python
def test_builds_platform_dimension_tasks_in_stable_order() -> None:
    plan = CommunityDiscoveryPlan(
        institution_code="peking-university",
        institution_name="北京大学",
        platforms=["zhihu", "tieba"],
        dimensions=ALL_DIMENSIONS,
    )
    tasks = build_community_agent_tasks(plan)
    assert len(tasks) == 14
    assert (tasks[0].platform, tasks[0].dimension) == ("zhihu", "school")
    assert (tasks[-1].platform, tasks[-1].dimension) == ("tieba", "student_club")


def test_missing_skill_fails_closed(tmp_path: Path) -> None:
    with pytest.raises(CommunityAgentSkillNotConfigured):
        load_community_agent_skill(tmp_path / "SKILL.md")


def test_task_rendering_does_not_expose_secrets(skill: CommunityAgentSkill) -> None:
    text = render_community_agent_task(
        skill,
        CommunityAgentTask(
            institution_code="peking-university",
            institution_name="北京大学",
            platform="zhihu",
            dimension="course",
        ),
        max_candidates=30,
    )
    assert "北京大学" in text
    assert "zhihu" in text
    assert "DEEPSEEK_API_KEY" not in text
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_agent_skill.py -q
```

Expected: collection fails because `community_agent_skill` and task models do not exist.

- [ ] **Step 3: Implement settings and the strict loader**

Add bounded settings:

```python
community_agent_enabled: bool = False
community_agent_model: str = ""
community_agent_max_steps: int = Field(default=40, ge=5, le=80)
community_agent_max_candidates: int = Field(default=30, ge=1, le=100)
community_agent_task_delay_seconds: float = Field(default=5.0, ge=0.0, le=60.0)
community_agent_browser_headless: bool = True
community_agent_skill_path: str = "skills/uniprism-university-community-crawler/SKILL.md"
deepseek_api_key: str = ""
deepseek_base_url: str = ""
deepseek_dialogue_model: str = "deepseek-chat"
```

The loader must parse YAML front matter, require `name: uniprism-university-community-crawler`, require a non-empty body, and raise `CommunityAgentSkillNotConfigured` on any invalid file.

- [ ] **Step 4: Write the runtime Skill**

The Skill must explicitly direct the Agent to:

1. search only the assigned institution, platform, and dimension;
2. use public search pages and public result pages;
3. visit a page before submitting its content;
4. call `submit_community_evidence` for each useful item;
5. stop at login walls, CAPTCHA, access denial, three no-progress actions, max steps, or candidate limit;
6. never submit search snippets, invented facts, usernames, profiles, contact details, ads, or unrelated school content.

- [ ] **Step 5: Run tests and verify GREEN**

Run the Task 1 test command and expect all tests to pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add .crawler_scaffold/university-crawler/skills \
  .crawler_scaffold/university-crawler/src/university_crawler/config.py \
  .crawler_scaffold/university-crawler/src/university_crawler/community_models.py \
  .crawler_scaffold/university-crawler/src/university_crawler/community_agent_skill.py \
  .crawler_scaffold/university-crawler/tests/test_community_agent_skill.py
git commit -m "feat(crawler): define community agent skill"
```

### Task 2: Strict community evidence collector

**Files:**
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_agent_collector.py`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_agent_collector.py`

**Interfaces:**
- Consumes: `CommunityAgentTask`, `CommunityEvidenceCandidate`.
- Produces: `CommunityEvidenceSubmission`.
- Produces: `CommunityAgentCollector.submit(input) -> str`.
- Produces: `CommunityAgentCollector.candidates`.

- [ ] **Step 1: Write failing collector tests**

Test these real decisions independently:

```python
def test_accepts_matching_public_evidence() -> None:
    collector = CommunityAgentCollector(task=zhihu_course_task(), limit=2)
    result = collector.submit(CommunityEvidenceSubmission(
        url="https://www.zhihu.com/question/123",
        title="北京大学课程体验",
        text="我在北京大学选课时发现，通识课和专业课需要提前规划。",
    ))
    assert result == "accepted"
    assert len(collector.candidates) == 1


@pytest.mark.parametrize("url", [
    "https://tieba.baidu.com/p/123",
    "https://example.com/post/123",
])
def test_rejects_wrong_platform_url(url: str) -> None:
    collector = CommunityAgentCollector(task=zhihu_course_task(), limit=2)
    assert collector.submit(valid_submission(url=url)) == "rejected_platform"


def test_rejects_other_university_and_contact_details() -> None:
    collector = CommunityAgentCollector(task=zhihu_course_task(), limit=2)
    assert collector.submit(valid_submission(
        text="清华大学课程不错，加微信 abc123 了解详情",
    )) == "rejected_scope"


def test_rejects_after_candidate_limit() -> None:
    collector = CommunityAgentCollector(task=zhihu_course_task(), limit=1)
    assert collector.submit(valid_submission()) == "accepted"
    assert collector.submit(valid_submission(url="https://www.zhihu.com/question/2")) == "limit_reached"
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_agent_collector.py -q
```

Expected: import fails because the collector module does not exist.

- [ ] **Step 3: Implement minimal collector**

Use existing `evaluate_public_url` for domain decisions. Create deterministic external IDs from canonical URL plus content fingerprint. Strip phone, QQ, WeChat, email, and profile fields before constructing `CommunityEvidenceCandidate`. Return explicit status strings so Agent feedback is actionable without exposing rejected text.

- [ ] **Step 4: Add URL and normalized-text deduplication tests**

Assert the same canonical URL and repeated normalized body return `duplicate` and do not increase the candidate count.

- [ ] **Step 5: Run tests and verify GREEN**

Run the Task 2 test command and expect all tests to pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add .crawler_scaffold/university-crawler/src/university_crawler/community_agent_collector.py \
  .crawler_scaffold/university-crawler/tests/test_community_agent_collector.py
git commit -m "feat(crawler): validate agent community evidence"
```

### Task 3: Browser Use + DeepSeek runtime adapter

**Files:**
- Create: `.crawler_scaffold/university-crawler/src/university_crawler/community_agent.py`
- Modify: `.crawler_scaffold/university-crawler/pyproject.toml`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_agent.py`

**Interfaces:**
- Consumes: rendered Skill task, `Settings`, and `CommunityAgentCollector`.
- Produces: `run_community_agent_task(task, skill, settings, runtime_factory=...) -> CommunityAgentTaskResult`.
- Internal protocol: `CommunityAgentRuntime.run(task_text, max_steps, on_submit) -> AgentRuntimeHistory`.
- Production factory lazily imports `Agent`, `Browser`, `ChatDeepSeek`, and `Tools` from `browser_use`.

- [ ] **Step 1: Write failing adapter tests with a fake runtime**

```python
async def test_runs_deepseek_agent_and_closes_browser() -> None:
    runtime = FakeRuntime(submissions=[valid_submission()])
    result = await run_community_agent_task(
        zhihu_course_task(),
        loaded_skill(),
        agent_settings(),
        runtime_factory=lambda *_args: runtime,
    )
    assert result.status == "completed"
    assert result.steps == 3
    assert result.pages_visited == 2
    assert len(result.candidates) == 1
    assert runtime.closed is True


async def test_missing_deepseek_key_does_not_start_runtime() -> None:
    called = False
    with pytest.raises(CommunityAgentNotConfigured):
        await run_community_agent_task(
            zhihu_course_task(),
            loaded_skill(),
            Settings(deepseek_api_key=""),
            runtime_factory=lambda *_args: mark_called(),
        )
    assert called is False
```

Also test login wall, CAPTCHA, and 403 classification from Agent history into `blocked_login`, `blocked_captcha`, and `blocked_access`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_agent.py -q
```

Expected: import fails because the adapter does not exist.

- [ ] **Step 3: Implement the injected runtime boundary**

The production runtime must use:

```python
llm = ChatDeepSeek(
    model=settings.community_agent_model
        or settings.deepseek_dialogue_model
        or "deepseek-chat",
    api_key=settings.deepseek_api_key,
    base_url=settings.deepseek_base_url or None,
)
browser = Browser(
    headless=settings.community_agent_browser_headless,
    executable_path=settings.crawler_browser_executable_path or None,
    allowed_domains=allowed_domains_for(task.platform),
    keep_alive=False,
)
agent = Agent(
    task=task_text,
    llm=llm,
    browser=browser,
    tools=tools,
    extend_system_message=skill.body,
    use_vision=False,
    max_failures=3,
    calculate_cost=True,
)
history = await agent.run(max_steps=settings.community_agent_max_steps)
```

Register `submit_community_evidence` with a Pydantic `param_model`, and always close the browser in `finally`. Keep Browser Use imports inside the production factory so unit tests do not require a real browser.

- [ ] **Step 4: Pin Browser Use**

Add:

```toml
"browser-use>=0.12,<0.13",
```

Do not add Browser Use Cloud or proxy dependencies.

- [ ] **Step 5: Run tests and verify GREEN**

Run the Task 3 test command and expect all tests to pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add .crawler_scaffold/university-crawler/pyproject.toml \
  .crawler_scaffold/university-crawler/src/university_crawler/community_agent.py \
  .crawler_scaffold/university-crawler/tests/test_community_agent.py
git commit -m "feat(crawler): run DeepSeek browser agent"
```

### Task 4: Agent task orchestration, deduplication, and CLI

**Files:**
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_runner.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/community_ingestion.py`
- Modify: `.crawler_scaffold/university-crawler/src/university_crawler/main.py`
- Modify: `.crawler_scaffold/university-crawler/tests/test_community_runner.py`
- Modify: `.crawler_scaffold/university-crawler/tests/test_community_ingestion.py`
- Create: `.crawler_scaffold/university-crawler/tests/test_community_agent_cli.py`

**Interfaces:**
- Produces: `DiscoveryMode = Literal["agent", "search_api", "legacy"]`.
- Extends: `run_community_pilot(..., discovery_mode="agent", agent_task_runner=...)`.
- Extends upload payload with optional `agentMetadata`.
- CLI: `--community --discovery-mode agent [--platform all] [--dimension all|...]`.

- [ ] **Step 1: Write failing runner tests**

Assert:

- Agent mode generates fourteen tasks for `platform=all`, `dimension=all`.
- A blocked Zhihu task does not stop the next Zhihu dimension or any Tieba task.
- Candidate deduplication happens across all task results before upload.
- Agent mode never reads `brave_search_api_key`.
- Explicit `search_api` retains the current `DISCOVERY_NOT_CONFIGURED` status.
- `COMMUNITY_AGENT_ENABLED=false` returns `AGENT_DISABLED` before model/browser startup.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_runner.py .crawler_scaffold/university-crawler/tests/test_community_agent_cli.py -q
```

Expected: new mode and CLI assertions fail.

- [ ] **Step 3: Implement Agent orchestration**

Add counts:

```python
"planned_tasks", "completed_tasks", "blocked_tasks", "failed_tasks",
"agent_steps", "pages_visited", "candidates_submitted",
"duplicates_removed"
```

Sleep only between real tasks, not in tests with an injected delay function. Build upload metadata with engine, model, skill version, task counts, and a bounded list of block-reason counts.

- [ ] **Step 4: Extend upload payload and tests**

Send:

```json
{
  "agentMetadata": {
    "executionEngine": "browser-use-agent",
    "agentModel": "deepseek-chat",
    "skillVersion": "uniprism-community-v1",
    "taskCounts": {},
    "blockedReasons": {}
  }
}
```

Never include raw Agent thoughts, prompts, keys, cookies, or rejected text.

- [ ] **Step 5: Run tests and verify GREEN**

Run Task 4 tests plus the existing community crawler suite.

- [ ] **Step 6: Commit Task 4**

```bash
git add .crawler_scaffold/university-crawler/src/university_crawler \
  .crawler_scaffold/university-crawler/tests
git commit -m "feat(crawler): orchestrate community agent tasks"
```

### Task 5: Backend metadata validation and content-monitoring display

**Files:**
- Modify: `.backend_patch/lib/content-ingestion/communityIngestion.ts`
- Modify: `.backend_patch/lib/adminContentIngestion.ts`
- Modify: `.backend_patch/app/admin/content-ingestion/page.tsx`
- Modify: `.backend_patch/app/admin/content-ingestion/AdminContentIngestionDashboardClient.tsx`
- Modify: `.backend_patch/tests/unit/communityIngestion.test.ts`
- Modify: `.backend_patch/tests/unit/adminContentIngestion.test.ts`
- Modify: `.backend_patch/tests/unit/communityEvidenceAdminPage.test.tsx`

**Interfaces:**
- Extends `communityIngestionPayloadSchema` with strict optional `agentMetadata`.
- Stores bounded metadata inside `ContentIngestionBatch.stageMetrics`.
- Exposes engine/model/task counts/block counts through the existing content-ingestion dashboard model.

- [ ] **Step 1: Write failing backend tests**

Add assertions that:

- valid Agent metadata is accepted and stored;
- unknown metadata keys are rejected;
- secrets, prompts, cookies, and raw thoughts are not valid fields;
- the admin dashboard labels `browser-use-agent` as `AI 浏览器 Agent`;
- invitation and unrelated admin modules are unchanged.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
npx vitest --config vitest.backend-patch.config.ts run \
  .backend_patch/tests/unit/communityIngestion.test.ts \
  .backend_patch/tests/unit/adminContentIngestion.test.ts \
  .backend_patch/tests/unit/communityEvidenceAdminPage.test.tsx
```

Expected: schema and dashboard assertions fail.

- [ ] **Step 3: Implement strict metadata schema**

Use bounded Zod records:

```typescript
const countRecord = z.record(
  z.string().regex(/^[a-z_]{2,40}$/),
  z.number().int().min(0).max(1_000_000),
).default({});
```

Limit model and skill strings to 120 characters and blocked-reason entries to known normalized reason keys. Merge metadata into existing `stageMetrics` without storing prompts or page content.

- [ ] **Step 4: Display Agent execution summary**

Only in `/admin/content-ingestion`, show engine, model, completed/blocked/failed task counts, Agent steps, visited pages, submitted candidates, and deduplicated candidates. Do not add controls or content to invitation management, user management, or App screens.

- [ ] **Step 5: Run tests and verify GREEN**

Run the Task 5 Vitest command and expect all tests to pass.

- [ ] **Step 6: Commit Task 5**

```bash
git add .backend_patch/lib/content-ingestion/communityIngestion.ts \
  .backend_patch/lib/adminContentIngestion.ts \
  .backend_patch/app/admin/content-ingestion \
  .backend_patch/tests/unit
git commit -m "feat(admin): monitor browser agent collection"
```

### Task 6: Deployment assets and operator documentation

**Files:**
- Modify: `.crawler_scaffold/university-crawler/README.md`
- Modify: `deploy/uniprism-community-evidence-pilot/README.md`
- Modify: `deploy/uniprism-community-evidence-pilot/deploy.sh`
- Modify: `deploy/uniprism-community-evidence-pilot/systemd/uniprism-community-evidence.service`
- Test: `.crawler_scaffold/university-crawler/tests/test_community_agent_deployment.py`

**Interfaces:**
- Service command uses `--discovery-mode agent --scheduled`.
- Deploy script verifies `DEEPSEEK_API_KEY`, Skill file, Chromium executable, backend token, and Browser Use import.
- Deployment leaves the timer disabled until manual smoke validation succeeds.

- [ ] **Step 1: Write failing deployment contract tests**

Read deployment files as text and assert:

- service contains `--discovery-mode agent` and `--scheduled`;
- deploy script no longer requires `BRAVE_SEARCH_API_KEY`;
- deploy script verifies the Skill file and `DEEPSEEK_API_KEY`;
- timer remains disabled by deployment;
- README includes manual single-task smoke command and log command.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests/test_community_agent_deployment.py -q
```

Expected: current deployment still requires Brave and lacks Agent flags.

- [ ] **Step 3: Update deployment**

Install the crawler editable package into its existing venv, reuse configured Chromium, copy the Skill directory, check dependencies, and restart only the community evidence service/worker components already in scope.

- [ ] **Step 4: Document operator flow**

Document:

```bash
systemctl start uniprism-community-evidence.service
journalctl -u uniprism-community-evidence.service -f
systemctl enable --now uniprism-community-evidence.timer
systemctl disable --now uniprism-community-evidence.timer
```

Also document that the first manual smoke run uses one platform and one dimension and that unreviewed content cannot reach App answers.

- [ ] **Step 5: Run tests and verify GREEN**

Run Task 6 tests and expect all tests to pass.

- [ ] **Step 6: Commit Task 6**

```bash
git add .crawler_scaffold/university-crawler/README.md \
  .crawler_scaffold/university-crawler/tests/test_community_agent_deployment.py \
  deploy/uniprism-community-evidence-pilot
git commit -m "docs: deploy runtime community agent"
```

### Task 7: Full verification and deployment bundle

**Files:**
- Regenerate: `deploy/uniprism-community-evidence-pilot/backend.tar.gz`
- Regenerate: `deploy/uniprism-community-evidence-pilot/crawler.tar.gz`
- Regenerate: `deploy/uniprism-community-evidence-pilot.tar.gz`

**Interfaces:**
- Produces a reproducible deployment archive containing the exact verified source state.

- [ ] **Step 1: Run the complete crawler test suite**

```powershell
& '.crawler_scaffold/university-crawler/.venv/Scripts/python.exe' -m pytest .crawler_scaffold/university-crawler/tests -q
```

Expected: all tests pass without network access.

- [ ] **Step 2: Run the complete backend unit suite**

```powershell
npx vitest --config vitest.backend-patch.config.ts run .backend_patch/tests/unit
```

Expected: all tests pass.

- [ ] **Step 3: Validate Prisma and build Next.js**

```powershell
npx prisma validate --schema .backend_patch/prisma/schema.prisma
npm run build
```

Expected: Prisma schema valid and production build exits zero.

- [ ] **Step 4: Perform a local fake-Agent smoke run**

Run one injected fake Agent task through the real runner and mock backend transport. Verify counts, candidate validation, upload metadata, and browser-close state.

- [ ] **Step 5: Regenerate archives**

Build the crawler archive from `.crawler_scaffold/university-crawler`, backend archive from only the content-ingestion files in scope, and the outer deployment archive from `deploy/uniprism-community-evidence-pilot`.

- [ ] **Step 6: Inspect archive manifests**

Confirm the outer archive contains:

- deployment script;
- systemd service/timer;
- backend archive;
- crawler archive;
- runtime Skill;
- no `.env`, Key, Cookie, browser profile, local database, node_modules, venv, screenshots, or user Flutter changes.

- [ ] **Step 7: Commit verified deployment assets**

```bash
git add deploy/uniprism-community-evidence-pilot \
  deploy/uniprism-community-evidence-pilot.tar.gz
git commit -m "build: package runtime community agent"
```

## Plan Self-Review

- Every design requirement is covered by Tasks 1–7.
- The runtime Agent and Skill are independently testable from the existing cleaner and backend.
- Browser Use and DeepSeek are imported only by the production adapter; unit tests use injected runtimes.
- The plan contains no requirement to configure Brave Search.
- The plan does not modify invitation management, unrelated admin pages, or user Flutter files.
- Secret-bearing fields and raw Agent thoughts have no storage path.

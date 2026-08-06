# 1.2 Flutter App/Web Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将已有 1.2 Flutter 交互原型接入正式 Learning Session API，使 Android App 与 Flutter Web 共用同一页面、同一后端会话和同一学习成果；保留显式本地 Mock 开关用于无后端演示。

**Architecture:** 先把 `AuthService` 的 `dart:io HttpClient` 抽成条件导入的跨端 HTTP Transport，再新增 `RemoteExplorationApi` 与远程 Session Controller。服务端树快照是事实源，Flutter 负责乐观 loading、渲染、重试和响应式布局。现有 Mock Repository/Gateway 继续作为显式开发模式，不做线上静默降级，避免用户误以为已保存到后端。

**Tech Stack:** Flutter/Dart、Material 3、package:http、ChangeNotifier、conditional imports、flutter_test、Flutter Web。

## Global Constraints

- 仓库：`D:\dev\Uniprism\uniprism_app`，分支：`feature/student-dialogue-exploration-1-2`。
- 遵守 `docs/DEVELOPMENT_CODE_STANDARD.md`，保持网络、DTO、编排与 UI 分层。
- App 和 Web 只维护一套 `lib/features/dialogue_exploration` 页面，不新增 Next.js 学生页面。
- 默认在 API 可配置时使用远程服务；本地 Mock 必须由 `DIALOGUE_EXPLORATION_USE_MOCK=true` 明确开启，远程失败只显示重试，不自动切 Mock。
- 客户端不生成服务端节点 ID、不自行评估策略、不宣称记忆卡已进入 2.2；一切以 API 快照为准。
- Web 必须消除 `dart:io` 编译依赖，并使用浏览器 credentials 维持匿名 cookie；App 保留 bearer token、匿名 ID 与 Set-Cookie 行为。
- 每个写请求发送 UUID 风格 `Idempotency-Key`，网络超时后重试复用相同 key。
- 页面同时覆盖 390px 手机宽度和 1280px Web 桌面宽度。

---

## Task 1: 抽取可在 Android 与 Web 共用的 HTTP Transport

**Files:**

- Create: `lib/network/app_http_transport.dart`
- Create: `lib/network/app_http_transport_stub.dart`
- Create: `lib/network/app_http_transport_io.dart`
- Create: `lib/network/app_http_transport_web.dart`
- Modify: `lib/main.dart`
- Test: `test/network/app_http_transport_test.dart`
- Test: `test/auth_service_request_test.dart`

**Step 1: 写 Transport 与 AuthService 失败测试**

使用可注入 fake client 验证：GET/POST JSON；统一超时；`{ok,data,error}` envelope；Authorization、`X-Anonymous-Id`、`X-Miniapp-Client`、`Idempotency-Key`；401 保留现有语义；Web 不手工设置 Origin/Cookie；App 能解析 Set-Cookie。

```dart
final data = await service.requestJson(
  'POST',
  '/api/learning-sessions/s1/turns',
  body: {'question': '为什么？'},
  headers: {'Idempotency-Key': 'trace-1'},
);
expect(data['session']['id'], 's1');
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/network/app_http_transport_test.dart test/auth_service_request_test.dart`

Expected: FAIL，跨端 transport 和公开方法尚不存在。

**Step 3: 定义与平台无关接口**

```dart
abstract interface class AppHttpTransport {
  Future<AppHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Object? jsonBody,
    required Duration timeout,
  });

  void close();
}

AppHttpTransport createAppHttpTransport() => createPlatformHttpTransport();
```

`app_http_transport.dart` 使用条件导入：IO → `app_http_transport_io.dart`，HTML → `app_http_transport_web.dart`，其他平台 → stub。

**Step 4: 实现平台 Transport**

- IO 端用 `package:http` 的 `IOClient`，允许设置 App 请求头并把 response headers 暴露给 AuthService。
- Web 端用 `package:http/browser_client.dart` 的 `BrowserClient()..withCredentials = true`；不设置浏览器禁止的 `Origin/Cookie`，由浏览器管理 cookie。
- 统一把网络异常转换为 `ApiRequestException`，响应正文 UTF-8 解码。

**Step 5: 重构 AuthService**

删除 `lib/main.dart` 顶层 `import 'dart:io';`，以状态码常量替代 `HttpStatus.unauthorized`；把私有 `_request` 改为可供特性层调用的：

```dart
Future<Map<String, dynamic>> requestJson(
  String method,
  String path, {
  Map<String, dynamic>? body,
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 30),
})
```

内部方法可继续委托 `requestJson`，避免一次性改动所有调用点。新增构造注入仅供测试，不改变 `AuthService.instance`。

**Step 6: 测试、Web 编译检查并提交**

Run:

```powershell
flutter test test/network/app_http_transport_test.dart test/auth_service_request_test.dart
flutter analyze lib/main.dart lib/network
flutter build web --debug --dart-define=API_BASE_URL=http://localhost:3000
```

Expected: 测试和 analyze 通过，Web 不再报 `dart:io`/`HttpClient` 不支持。

Commit: `git commit -m "refactor(network): support shared app and web requests"`

---

## Task 2: 定义远程 API DTO、解析器与幂等客户端

**Files:**

- Create: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Create: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Test: `test/features/dialogue_exploration/remote_exploration_dto_test.dart`
- Test: `test/features/dialogue_exploration/remote_exploration_api_test.dart`

**Step 1: 写 DTO 解析失败测试**

固定一份完整 JSON fixture，覆盖 Session、节点树、素材、策略、限制、总结；未知素材类型降级为不可交互提示卡；缺失必要节点 ID、非法 parentId、非 ISO 时间必须抛出可诊断的 `FormatException`。

**Step 2: 运行测试确认失败**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_dto_test.dart test/features/dialogue_exploration/remote_exploration_api_test.dart`

Expected: FAIL。

**Step 3: 实现远程快照模型与映射**

```dart
final class RemoteLearningSessionSnapshot {
  const RemoteLearningSessionSnapshot({
    required this.sessionId,
    required this.status,
    required this.topic,
    required this.expiresAt,
    required this.currentNodeId,
    required this.nodes,
    required this.materials,
    required this.activeStrategy,
    required this.limits,
    required this.summary,
  });
}
```

映射到已有 `ExplorationTree/ExplorationNode/ExplorationMaterial` 时保留服务端 ID、`strategyMode/goal/reason`、回溯目标和支线标记。新增字段应通过具名参数和默认值兼容本地 Mock 测试。

**Step 4: 实现 RemoteExplorationApi**

```dart
abstract interface class ExplorationApiClient {
  Future<RemoteLearningSessionSnapshot> createSession(CreateSessionCommand command);
  Future<RemoteLearningSessionSnapshot> getSession(String sessionId);
  Future<RemoteLearningSessionSnapshot> submitTurn(SubmitTurnCommand command);
  Future<RemoteLearningSessionSnapshot> createBranch(CreateBranchCommand command);
  Future<RemoteLearningSessionSnapshot> backtrack(BacktrackCommand command);
  Future<RemoteLearningSessionSnapshot> complete(CompleteSessionCommand command);
  Future<String> createMemoryCandidate(CreateMemoryCandidateCommand command);
  Future<List<int>> exportSession(String sessionId);
}
```

`RemoteExplorationApi` 通过注入的 `AuthService.requestJson` 调用后端；每个命令持有 `clientTraceId`，重试不新建 ID。所有请求都携带由 `ensureExploreSession()` 得到的 `exploreSessionId`。

**Step 5: 测试并提交**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_dto_test.dart test/features/dialogue_exploration/remote_exploration_api_test.dart`

Expected: PASS。

Commit: `git commit -m "feat(dialogue): add production learning session api client"`

---

## Task 3: 建立本地/远程统一 Session Coordinator

**Files:**

- Create: `lib/features/dialogue_exploration/core/exploration_session_coordinator.dart`
- Create: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Modify: `lib/features/dialogue_exploration/core/teaching_session_controller.dart`
- Modify: `lib/features/dialogue_exploration/dialogue_exploration.dart`
- Test: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`
- Test: `test/features/dialogue_exploration/exploration_session_coordinator_test.dart`

**Step 1: 写状态机失败测试**

覆盖：idle → starting → active → submitting → active；网络失败 → failed 但保留旧树；retry 复用 clientTraceId；restore 根据 sessionId 拉取服务端树；complete → completed；dispose 后异步响应不 notify；同一时刻只允许一个写操作。

**Step 2: 定义 UI 依赖的最小统一接口**

```dart
abstract interface class ExplorationSessionCoordinator
    implements Listenable {
  ExplorationSessionViewState get state;
  Future<void> start(ExplorationStartRequest request);
  Future<void> restore(String sessionId);
  Future<void> submitQuestion(String question, {String? branchFromNodeId});
  Future<void> backtrack(String targetNodeId);
  Future<void> complete(String reflection);
  Future<String> convertNodeToMemory(String nodeId);
  Future<void> export();
}
```

`ExplorationSessionViewState` 统一 `status/scenario/tree/materials/activeStrategy/summary/error/limits/expiresAt`，UI 不区分本地或远程。

**Step 3: 适配现有本地 Controller**

保留已有 `TeachingSessionController` 的 Mock 逻辑与测试，通过实现 Coordinator 或增加轻量 adapter；将旧限制调整为 20/5/3，与正式服务一致。Mock 仅供显式开发模式。

**Step 4: 实现远程 Controller**

远程 Controller 不运行本地 `TeachingStrategyEngine`，而是把 API 快照原子替换进 state。提交时先保存 `PendingOperation(type,payload,clientTraceId)`；失败保留；点击重试复用；成功后清空。防止客户端先插入永久节点造成双端树分叉。

**Step 5: 测试并提交**

Run: `flutter test test/features/dialogue_exploration/remote_exploration_session_controller_test.dart test/features/dialogue_exploration/exploration_session_coordinator_test.dart test/features/dialogue_exploration/adaptive_teaching_session_test.dart`

Expected: PASS。

Commit: `git commit -m "feat(dialogue): coordinate remote and mock learning sessions"`

---

## Task 4: 配置运行模式并接入开发者入口

**Files:**

- Modify: `lib/app_config.dart`
- Modify: `lib/developer_tools.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_lab_page.dart`
- Modify: `lib/features/dialogue_exploration/dialogue_exploration_demo.dart`
- Test: `test/features/dialogue_exploration/dialogue_runtime_selection_test.dart`
- Test: `test/features/dialogue_exploration/exploration_page_test.dart`

**Step 1: 写运行模式选择失败测试**

覆盖：默认远程；`DIALOGUE_EXPLORATION_USE_MOCK=true` 才选择本地；远程失败显示失败/重试而非偷偷切 Mock；开发者工具入口仍是 `兴趣探索 → 开发者工具 → 1.2 对话探索`。

**Step 2: 实现配置**

```dart
static const dialogueExplorationUseMock = bool.fromEnvironment(
  'DIALOGUE_EXPLORATION_USE_MOCK',
  defaultValue: false,
);
```

不再增加“选择掌握程度/选择模式”的实验菜单。真实入口是：

- 原子入口：接收 `atomId/scenarioId/hookQuestion` 直接创建 Session。
- 问题入口：首页展示种子问题与一个自由输入框，提交后创建 Session。

Mock 场景标签明确显示“本地演示数据”，远程模式不显示 Mock 提示。

**Step 3: 注入 API 与 Coordinator Factory**

开发者页创建 `RemoteExplorationApi(AuthService.instance)`，再创建 `RemoteExplorationSessionController`。页面只接收 factory/接口，不直接引用 AuthService 单例，保证 widget test 可替换。

**Step 4: 测试并提交**

Run: `flutter test test/features/dialogue_exploration/dialogue_runtime_selection_test.dart test/features/dialogue_exploration/exploration_page_test.dart`

Expected: PASS。

Commit: `git commit -m "feat(dialogue): enable production runtime from developer tools"`

---

## Task 5: 完成对话讲台、思维树和素材的响应式交互

**Files:**

- Modify: `lib/features/dialogue_exploration/presentation/exploration_lab_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_session_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_tree_panel.dart`
- Modify: `lib/features/dialogue_exploration/materials/exploration_material_card.dart`
- Modify: `lib/features/dialogue_exploration/materials/parabola_painter.dart`
- Test: `test/features/dialogue_exploration/exploration_responsive_page_test.dart`
- Test: `test/features/dialogue_exploration/exploration_remote_flow_test.dart`
- Test: `test/features/dialogue_exploration/exploration_material_test.dart`

**Step 1: 写移动端与桌面端失败测试**

在 `390x844` 验证单列对话、底部输入、思维树抽屉；在 `1280x800` 验证左侧对话讲台 + 右侧实时树，输入框不被遮挡，点击树节点能回溯/开支线。验证 loading 禁止重复发送、错误横幅可重试、完成后显示总结/导出/记忆候选。

**Step 2: 重构问题优先首页**

首屏只显示：标题“今天想弄懂什么？”、自由输入、3–4 个 Mock/远程种子问题、最近未完成会话（若有）。不要求学生选择 5 种策略或掌握程度；掌握度从服务端画像/Mock 场景得到。

**Step 3: 重构 Session 页面**

- 对话区每轮显示学生问题、导师回答、明确反问和策略自然语言标签。
- 问题脚手架只插入模板：“是什么 / 为什么会这样 / 如果……会怎样 / 与 X 有什么关系 / 有什么用”，不填写答案。
- 桌面两栏：`Expanded(flex: 3)` 对话、`ConstrainedBox(maxWidth: 420)` 思维树。
- 手机单列：顶部树进度按钮打开 `DraggableScrollableSheet`。
- 选择旧节点后提供“从这里继续”与“回到这里”，不删除后续路径。
- 接近 10 分钟或限制时显示收口提示，由服务端决定最终 SELF_EXPLANATION。

**Step 4: 实现四类素材真实呈现**

- 图：本地/远程图片和概念图，失败时显示标题与说明。
- 视频：使用项目既有视频能力；若尚无播放器依赖，第一阶段提供可播放的 Web/系统链接按钮并明确不是交互组件，不能伪装成静态视频截图。
- 交互：`parabola_widget`、`sign_flip_widget`、`unit_economics_widget`、`step_order_widget` 在流内改变参数并回传 interaction event。
- 公式卡：使用现有文本/公式渲染；展示推导步骤，可折叠。

未知交互 component key 显示“当前版本暂不支持该互动素材”，不把图片冒充交互。

**Step 5: 测试并提交**

Run:

```powershell
flutter test test/features/dialogue_exploration/exploration_responsive_page_test.dart test/features/dialogue_exploration/exploration_remote_flow_test.dart test/features/dialogue_exploration/exploration_material_test.dart
```

Expected: PASS。

Commit: `git commit -m "feat(dialogue): build responsive interactive learning stage"`

---

## Task 6: 完成保存、恢复、总结、记忆候选与导出体验

**Files:**

- Create: `lib/features/dialogue_exploration/adapters/exploration_session_store.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_session_page.dart`
- Modify: `lib/features/dialogue_exploration/core/exploration_outputs.dart`
- Test: `test/features/dialogue_exploration/exploration_restore_test.dart`
- Test: `test/features/dialogue_exploration/exploration_completion_test.dart`

**Step 1: 写失败测试**

覆盖：创建成功后本地只保存 session ID；页面重开从后端恢复；已完成会话只读；复述为空不能完成；完成后显示理解证据、错误模型、兴趣方向；勾选导师节点生成 `PENDING` 记忆候选；重复勾选不重复；导出 Web 下载和 Android 分享/保存走平台适配。

**Step 2: 实现轻量 Session Store**

只持久化当前 `learningSessionId` 与最近会话 ID 列表，不保存整棵树作为事实源。登录/匿名身份切换时清除不属于当前 scope 的最近列表。

```dart
abstract interface class ExplorationSessionStore {
  Future<String?> readActiveSessionId(String identityScope);
  Future<void> saveActiveSessionId(String identityScope, String sessionId);
  Future<void> clearActiveSessionId(String identityScope);
}
```

**Step 3: 完成出口交互**

完成按钮先要求学生用自己的话复述；API 返回后展示总结。每个可转记忆项节点有独立勾选态和失败重试；成功提示“已生成复习候选，等待 2.2 接收”，不写“已加入复习”。

**Step 4: 测试并提交**

Run: `flutter test test/features/dialogue_exploration/exploration_restore_test.dart test/features/dialogue_exploration/exploration_completion_test.dart`

Expected: PASS。

Commit: `git commit -m "feat(dialogue): restore and complete cross-platform sessions"`

---

## Task 7: App/Web 联调、回归与运行说明

**Files:**

- Create: `docs/operations/dialogue-exploration-app-web-testing.md`
- Modify if required: `README.md`

**Step 1: 运行 1.2 全部 Flutter 测试**

Run:

```powershell
flutter test test/features/dialogue_exploration test/network/app_http_transport_test.dart test/auth_service_request_test.dart
flutter analyze lib/features/dialogue_exploration lib/network lib/main.dart
```

Expected: 全部退出码 0。

**Step 2: 构建 Web 与 Android 调试产物**

Run:

```powershell
flutter build web --debug --dart-define=API_BASE_URL=http://localhost:3000
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Expected: 两个构建均成功。Android 模拟器访问宿主机使用 `10.0.2.2`，Web 使用 `localhost`。

**Step 3: 启动正式远程联调**

Backend:

```powershell
npm run dev
```

Flutter Web:

```powershell
flutter run -d chrome --web-port 3001 --dart-define=API_BASE_URL=http://localhost:3000
```

Android emulator:

```powershell
flutter run -d emulator-5554 -t lib/main.dart --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

明确不要传 `DIALOGUE_EXPLORATION_USE_MOCK=true`，否则只会看到本地演示。

**Step 4: 执行跨端同会话验收**

1. Web 从“为什么负负得正？”创建 Session。
2. 连续追问，确认问题链 → 苏格拉底；输入错误思路，确认错误追踪与反例。
3. 新开支线并回溯，树保留两条路径。
4. 操作至少一个交互素材，再确认另一种素材形态。
5. App 以相同登录身份打开最近 Session，能读取相同服务端树；匿名身份只承诺同浏览器/同 App 存储域恢复。
6. 完成复述，查看总结；勾选节点生成记忆候选；导出 JSON。
7. Business Model Demo 至少 3 层、2 次旁散、3 类素材，无“你觉得呢”。

**Step 5: 写运行说明并提交**

文档记录两套启动命令、Mock 开关、常见 CORS/401/超时排查、数据库/Redis/DeepSeek 前置条件和当前知识库仍为 Mock 的限制。

Commit: `git commit -m "docs(dialogue): add app and web integration guide"`

---

## Definition of Done

- Android App 与 Flutter Web 可从同一 1.2 页面创建、推进、恢复、分支、回溯和完成正式后端 Session。
- 首页以学生问题为起点，不再要求选择教学模式或掌握程度。
- 五种策略自动组合；UI 只展示自然语言教学动作。
- 思维树实时反映服务端状态，移动端和桌面端均可操作。
- 素材至少两次且形态不单一；所有标记为交互的 Mock 组件真实可操作。
- 远程错误不静默切换本地 Mock；重试幂等且不产生重复节点。
- 总结、证据、记忆候选和导出均来自服务端，页面重启可恢复。
- 1.2 Flutter 测试、analyze、Web debug build 和 Android debug build 通过，并完成至少一次 localhost:3000 端到端联调。

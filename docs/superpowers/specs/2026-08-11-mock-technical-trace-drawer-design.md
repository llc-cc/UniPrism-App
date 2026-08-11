# Mock 技术轨迹抽屉设计

日期：2026-08-11  
状态：已确认设计，待实现  
范围：UniPrism 预习课堂 Flutter 前端演示切片

## 1. 来源与目标

本设计落实用户提供的《UniPrism 预习课堂 Teacher Agent × MCP 素材库展示设计》，不是新增的产品方向。原文明确要求：

- 采用“单节故事主线 + 可展开技术轨迹”，轨迹默认收起。
- 顶栏提供演示专用的“技术轨迹”开关。
- 抽屉展示教案节点、知识原子、学生证据、缺失证据、教学意图、动作、MCP 候选与命中版本、reason_code、耗时和 fallback。
- `REQ-DEMO-TRACE-001` 要求解释“为什么调用该素材”，但不得暴露隐藏推理。

第一版目标是在不依赖真实 MCP 的情况下，让现有教学阶段、证据和 Teacher Action 具备可演示的技术轨迹界面，并提前固定未来真实轨迹的数据边界。

## 2. 产品边界

第一版属于演示 Mock，不属于生产轨迹：

- 入口始终在课堂顶栏可见，名称为“技术轨迹 · Mock”。
- 抽屉默认关闭，由演示人员主动打开。
- Mock MCP 候选、过滤原因、版本和耗时必须明确标注为模拟数据。
- 现有 Session 中真实存在的阶段、知识原子、目标、证据、教学意图和 reasonCode 优先直接读取，不重复伪造。
- 不展示链式思维、模型内部草稿或对学生心理状态的推测。
- 正式环境接入前必须由真实后端轨迹替换 Mock Provider；前端写死数据不能满足生产验收。

## 3. 方案选择

采用“独立轨迹模型 + Mock Provider + 独立抽屉组件”。

没有选择把假数据直接写进课堂页面，因为这会把演示数据与 UI 耦合，真实 MCP 接入时需要重写。第一版也不增加后端 Mock API，避免当前阶段引入额外联调故障。

## 4. 组件与职责

### 4.1 TechnicalTraceSnapshot

只描述抽屉需要消费的可审查事实：

- 数据来源标识与是否为 Mock。
- 当前 Session、教案节点、知识原子和教学阶段。
- 当前目标、最近证据、证据强度、缺失证据。
- Teacher Action、教学意图和 reasonCode。
- MCP 工具名、请求摘要、候选数量、过滤结果、命中素材和精确版本。
- 分阶段耗时与总耗时。
- fallback 是否触发及其原因。

该模型不依赖 Widget，也不读取 BuildContext。

### 4.2 MockTechnicalTraceProvider

输入当前 `RemoteLearningSessionSnapshot`，输出 `TechnicalTraceSnapshot`。

Provider 遵循以下规则：

1. 教学阶段、目标、atomId、证据、教学意图和 reasonCode 来自现有 Session 快照。
2. 当前素材存在时，使用真实的 materialId、componentKey 和素材使用记录 ID。
3. MCP 候选、过滤、精确版本和耗时由确定性 Mock 场景补齐，相同输入生成相同输出，保证测试和演示可复现。
4. 不存在 `teachingFlow` 时返回“当前为开放探索，暂无引导式技术轨迹”，而不是伪造教学判断。
5. 不把 Mock 候选或模拟耗时写回 Session，不污染学习证据。

未来接入真实轨迹时，保留模型和抽屉，只将 Provider 替换为远程数据适配器。

### 4.3 TechnicalTraceDrawer

右侧抽屉按以下顺序展示：

1. Mock 数据警示。
2. 当前教学上下文。
3. 学习证据与缺失证据。
4. Teacher Agent 当前动作。
5. MCP 素材选择过程。
6. 耗时与 fallback 状态。

每个区块允许内容为空，但必须展示明确空态，不允许因为缺少某字段导致整个抽屉失败。

### 4.4 课堂页面接入

- `RemoteLearningSessionPage` 顶栏增加“技术轨迹 · Mock”入口。
- 点击后打开右侧 `endDrawer`。
- 抽屉从页面当前最新 Snapshot 构建，因此学生完成操作、进入微测或反思后，再次打开能够看到新的阶段和证据。
- 打开和关闭抽屉不得修改 Session、输入内容、滚动位置或当前树节点。

## 5. 数据流

```text
RemoteLearningSessionSnapshot
        ↓
MockTechnicalTraceProvider
        ↓
TechnicalTraceSnapshot
        ↓
TechnicalTraceDrawer
```

学生操作仍沿用现有链路提交后端；轨迹抽屉只读取返回的最新快照，不参与教学状态推进。

## 6. 错误与降级

- 没有教学流程：展示开放探索空态。
- 没有证据：展示“尚未产生可审查证据”。
- 没有素材：MCP 区块展示“当前动作不需要素材”。
- 未知阶段或未知 reasonCode：保留原始代码并展示通用说明，不抛出渲染异常。
- Mock Provider 内部异常：课堂保持正常，仅在抽屉展示“轨迹暂不可用”。

## 7. 测试与验收

采用测试先行，至少覆盖：

1. Provider 使用 Session 中真实的阶段、目标、证据和 reasonCode。
2. 不同教学阶段产生对应的确定性 Mock MCP 轨迹。
3. 无 `teachingFlow` 时返回开放探索空态。
4. 顶栏始终显示“技术轨迹 · Mock”入口。
5. 点击入口能够打开抽屉并看到 Mock 警示、教学上下文、证据和素材选择。
6. 打开与关闭抽屉不改变课堂快照和当前学习节点。
7. Widget 在素材或证据缺失时正常显示空态。

最低验证命令：

```text
dart analyze lib/main.dart test
flutter test test/features/dialogue_exploration/technical_trace_test.dart
flutter test test/features/dialogue_exploration/live_tree_page_test.dart
flutter test
```

## 8. 已知限制与后续替换

第一版不能通过 `REQ-DEMO-MCP-001` 的真实 MCP 验收，因为候选、过滤、版本和耗时仍为 Mock。它只先完成 `REQ-DEMO-TRACE-001` 的界面结构和解释能力原型。

后续真实接入需要：

- 后端返回版本化技术轨迹合同。
- 真实记录 MCP 请求、候选、过滤和命中版本。
- 真实记录 Agent、MCP、素材加载与 fallback 耗时。
- 增加权限控制，使技术轨迹仅对演示或授权角色可见。
- 移除 Mock 标识并替换 Provider，抽屉 UI 和模型保持兼容。

# 真实练习作答 V2 Shadow 判断设计

## 目标与边界

第一版遵守以下边界：Flutter App 负责产生并提交真实学生行为，后端负责内部判断，管理端通过模拟案例与独立 Gold 调试同一套规则。

- App 采集题目答案、解题过程、修改、切题、提示和提交事件，继续调用正式练习会话 API。
- 后端继续用 V1 完成学生反馈与正式画像，同时对同一真实作答运行 `cognition-rule-v2` Shadow 判断。
- V2 Shadow 随 attempt 内部 facts JSON 同事务保存，但不替换 V1 正式画像。
- 学生 DTO 不返回 Shadow、内部事实代码、错误标签或置信度。
- 管理端不新增真实学生作答接口，只用 19/190/12 Benchmark 和自定义模拟场景展示 Gold、Actual、Evidence 与偏差。

## 方案

采用“提交时 Shadow 快照”，不新增数据表。

1. 直接切换 V2：当前三项 Benchmark 指标仍为红色，不能影响正式学生档案。
2. 新增 V2 表：需要迁移、并发事务与历史回填，本轮没有必要。
3. Shadow 快照（采用）：提交时使用与 V1 相同的题目、答案、过程、尝试次数、前次结果和事件摘要运行 V2，把版本化单次证据嵌入 attempt facts。

Shadow 是提交时冻结的内部实验结果，便于后续训练投影和规则回归；它不是正式学生画像。

## 数据流

1. Flutter Web 远程模式创建或恢复练习会话。
2. 学生编辑答案与过程，App 防抖保存草稿并批量记录受限行为事件。
3. 提交前 App 刷新草稿与事件；后端以同题上一次提交时间为左边界切分当次事件，再形成 V1/V2 共用输入。
4. 后端运行 V1 正式评分，再运行 `assessAttemptCognitionV2`。
5. V1 facts 与 `cognitionV2Shadow` 在同一 attempt 事务内保存；V1 正式画像照常更新。
6. 学生只收到现有白名单反馈；管理端通过模拟 Benchmark 审查相同 V2 Engine。

## Shadow 契约

`cognitionV2Shadow` 至少保存：

- `assessorVersion = cognition-rule-v2`
- `outcome`
- 七个维度的 `status`、`band`、`confidence`、`evidenceQuality`、`evidenceStepIds`、`factCodes`、`errorTags`

非 `OBSERVED` 维度保持 `band = null`。Shadow 不保存额外一份答案或过程，避免重复敏感数据。

## 时序与幂等

- `previousOutcome` 只取同一会话、同一题目的前次结果。
- 首次提交使用同题全部已接收事件；后续提交仅使用 `receivedAt > previousSubmittedAt` 的事件，边界时刻事件归属前一次作答。
- V1 与 V2 共用该当次事件摘要；损坏或倒序时间线按 `DEGRADED` 保守处理。
- 幂等重复请求返回既有 attempt，不再次生成或累加 Shadow。
- 第一版只保存单次七维 Shadow，不写入 V1 `PracticeAbilityProfile`；长期 V2 状态继续由 Benchmark 轨迹验证。

## 管理端

Benchmark Debug 保持五个区域：总览、题目难度、行为案例、自定义场景、长期轨迹。模拟案例展示 Gold/Actual/Evidence/偏差；不得把 Engine 输出反过来当 Gold，也不读取真实学生答案或 Shadow。

## App 测试入口

```powershell
flutter run -d chrome --web-port=5173 `
  --dart-define=APP_ENV=development `
  --dart-define=ENABLE_DEVELOPER_TOOLS=true `
  --dart-define=PRACTICE_ASSESSMENT_REMOTE=true `
  --dart-define=API_BASE_URL=http://localhost:3000
```

从“开发者工具 → 练习评分实验室”进入。连接横幅必须显示后端会话而不是 Mock。

## 验收

- App 远程提交后，attempt 内部 facts 含版本化 V2 Shadow。
- 七维非观察项保持 `band=null`。
- 学生响应不包含 Shadow 或内部证据字段。
- 幂等重试不产生第二份 attempt 或重复证据。
- 同题旧提示、旧修改不会污染后续提交的当次证据。
- 静态 19/190/12 Benchmark 继续展示真实红绿基线。

## 限制

- 仅对新提交生成 Shadow，不回填旧 attempt。
- Shadow 暂不进入正式长期画像；达到 Benchmark 门槛后另行设计 V2 画像迁移。
- 管理端第一版不查看真实学生个案，只调试模拟 Gold。

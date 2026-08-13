# 练习评分模块 V1 交接说明

最后更新：2026-08-13

## 交付结果

练习评分与预习模块保持独立，Flutter 已接入真实 Next.js/MySQL 后端：

- 19 道自造数学演示题、六维题目难度和七维单次能力证据；
- 匿名身份、会话恢复、乐观草稿、事件去重、幂等提交和长期能力画像；
- 原生端参与者令牌写入 `uniprism/auth_storage`，Web 只使用 HttpOnly Cookie；
- 远程草稿输入停止 600ms 后自动保存，切题、退后台、完成整卷和销毁页面时尽力刷新；
- 登录绑定可同时携带 Bearer 与匿名参与者令牌，绑定成功后原生端立即删除匿名令牌；
- 学生响应只接收能力状态与档位，不接收内部置信度、事实码、错误标签或证据步骤 ID；
- 长期画像的 `displayBand: null` 保持为“证据不足”，不会映射成 0 档能力；
- 远程失败保留草稿并显示 request ID，不会静默切回 Mock；
- 标准答案与完整 rubric 只存在于服务端，不下发 Flutter；
- `rules` 是当前生产装配；双评校验器与训练投影已准备，但未连接具体外部模型。

当前试卷代码为 `cn-gaokao-2026-new-i-math-v1`，内容版本为 `demo-v1`。全部题目是项目自造内容，不是 2026 官方试题。

后端管理端现已增加独立的“能力判断测试台”：`http://localhost:3000/admin/practice-benchmark`。它只使用模拟 Gold（19 条题目难度 Gold、190 条行为基准案例、12 条长期轨迹和自定义内存场景），不依赖 Flutter 页面、不写学生数据库，也不切换线上 V1 画像。

## App 与后端职责边界

Flutter App 只负责题目、答案、解题过程、改答/切题和提交等可观察行为；Remote 模式将这些行为写入后端 V1 API。后端在 V1 正常处理之外，可将同一批行为送入 V2 Shadow 作独立比对；Shadow 的内部标签、评分、置信度和差异不下发给 App，App 不读取也不展示 Shadow 数据。管理端测试台仅以模拟 Gold 调试和评估 Shadow，不是学生真实作答入口。

```text
Flutter App（题目 / 答案 / 过程 / 提交）
  -> 后端 V1 API（真实会话、草稿、事件、提交）
  -> V2 Shadow（后台比对；不回传 App）

管理端 benchmark -> 模拟 Gold（仅管理端调试）
```

## 启动前置条件

后端仓库：`D:\ywkeji\Uniprism\UniPrism_New-main`

前端仓库：`D:\dev\Uniprism\uniprism_app`

先按后端 `docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md` 准备数据库。本次检查发现现有阿里云 alphatest 数据库迁移历史与仓库分叉，因此没有自动修改该数据库；推荐使用独立测试库。

数据库迁移与种子完成后启动后端：

```powershell
cd D:\ywkeji\Uniprism\UniPrism_New-main
$env:PRACTICE_ASSESSOR_MODE='rules'
$env:PRACTICE_WEB_ORIGINS='http://localhost:5173'
npm run dev
```

## 启动 Flutter 远程模式

已有 Flutter 页面进程不会自动获得新增的 `dart-define`，需要停止并重新启动：

```powershell
cd D:\dev\Uniprism\uniprism_app
flutter run -d chrome --web-port=5173 `
  --dart-define=APP_ENV=development `
  --dart-define=ENABLE_DEVELOPER_TOOLS=true `
  --dart-define=API_BASE_URL=http://localhost:3000 `
  --dart-define=PRACTICE_ASSESSMENT_REMOTE=true
```

进入：`首页 → 开发者工具 → 练习评分实验室`。

页面顶部横幅是运行模式的唯一现场识别：显示“后端已连接 · 会话 … · RULES”表示 Remote 已连接后端；显示“演示 Mock · 结果不会写入后端”表示本地 Mock，绝不能据此验收真实会话或数据写入。Remote 不展示、也不读取 V2 Shadow 的内部结果。

## Mock 模式

不准备数据库时可先验证 UI 与本地规则：

```powershell
flutter run -d chrome --web-port=5173 `
  --dart-define=ENABLE_DEVELOPER_TOOLS=true `
  --dart-define=PRACTICE_ASSESSMENT_REMOTE=false
```

Mock 模式会明确显示“结果不会写入后端”，不能用于验证重启恢复和数据库画像。

## 手工验收

1. 打开远程练习，确认返回 19 题且页面有非官方内容声明。
2. 在第 1 题只选最终答案、不写过程并提交；理解与推理应显示“过程证据不足”，不能显示 0 档。
3. 在解答题填写包含 rubric 关键步骤的过程，提交后检查七维证据。
4. 切换题目、关闭页面再打开，确认当前题号、答案、过程与已提交结果恢复。
5. 断开网络后提交，确认草稿仍保留、页面显示错误与重试入口；恢复网络后重试。
6. 相同草稿重复提交应返回同一幂等结果；一道题第 4 次正式提交应被拒绝。
7. 输入后等待约 600ms 或直接切题，再重开页面，草稿与最近题号应从服务端恢复。
8. 原生匿名会话登录绑定后，旧令牌应失效，并能从账号身份读取合并后的会话与画像。
7. 19 题均至少提交一次后完成整卷，检查后端会话状态和能力画像。

## 自动验证

### 此前基线验证记录

以下结果是本轮新增 Flutter 测试之前留下的基线记录，不是 2026-08-13 本轮的绿灯证据：练习模块静态分析无问题；练习模块 38 项测试通过；Flutter 全仓 218 项测试通过。

### 本轮 2026-08-13 验证状态

本轮运行时，正在运行的本项目 `flutter run` 持有 Flutter 工具启动锁。新增测试尚未取得绿灯：

- `flutter test test/widget_test.dart test/features/practice_assessment/practice_session_controller_test.dart` 无输出，60 秒后停止；
- `flutter test test/features/practice_assessment/practice_session_controller_test.dart` 无输出，120 秒超时（exit code 124）。

因此，本轮不能声称 Flutter 测试通过。

### 恢复与重跑顺序

先正常停止已知的本项目 Flutter Web `flutter run` 实例，再运行目标测试：

```powershell
dart analyze lib/features/practice_assessment test/features/practice_assessment
flutter test test/widget_test.dart test/features/practice_assessment/practice_session_controller_test.dart
```

目标测试取得绿灯后，才重新用本文件“启动 Flutter 远程模式”章节的 `flutter run -d chrome --web-port=5173 ...` 命令启动 Web 页面。

## 小模型怎么训练

第一阶段不直接让小模型输出一个总分，而是拆成两个监督任务：

1. 对每个能力维度分类 `OBSERVED / INSUFFICIENT_EVIDENCE / NOT_APPLICABLE`；
2. 只对 `OBSERVED` 维度预测 `0..4` 有序档位。

训练数据由服务端 `TrainingDatasetProjector` 生成，只接受存在独立训练授权、没有双评冲突且达到置信度门槛的去标识化样本。按学生分组哈希和题目结构族切分训练/验证/测试集，避免同一学生或同题改写泄漏。积累足够数据后可选中文数学能力较好的 1B–4B 基座做 QLoRA；上线前必须在冻结测试集验证证据状态 F1、有序分类误差和置信度校准。低置信度结果继续回退规则或返回证据不足。

本期没有训练权重、没有真实训练任务，也没有把学生作答发送到具体外部模型。这样做是为了先验证标签契约、隐私授权和数据质量，再承担模型成本。

## 已知限制

- 演示题不是官方真题，正式题库仍需授权内容与逐问 rubric。
- 规则评分无法证明任意数学表达式等价，关键词命中不等于完整证明正确。
- alphatest 数据库迁移历史尚未对齐，完成此项前远程页面无法进行真实数据库联调。
- 实证难度校准需要积累足够有效作答后才可发布。
- 登录绑定和跨设备画像已有后端契约，但当前实验室尚未提供独立的“立即绑定”按钮。
- Benchmark 的难度误差 ±1 命中率、观察档位命中率和画像方向一致率在第一版仍低于目标，管理端会显示红色基线；这正是下一轮调整 Engine 而不是调整 Gold 的输入。

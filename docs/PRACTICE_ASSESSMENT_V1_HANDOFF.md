# 练习评分模块 V1 交接说明

最后更新：2026-08-12

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

## 启动前置条件

后端仓库：`D:\ywkeji\Uniprism\UniPrism_New-main`

前端仓库：`D:\dev\Uniprism\uniprism_app`

先按后端 `docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md` 准备数据库。本次检查发现现有阿里云 alphatest 数据库迁移历史与仓库分叉，因此没有自动修改该数据库；推荐使用独立测试库。

数据库迁移与种子完成后启动后端：

```powershell
cd D:\ywkeji\Uniprism\UniPrism_New-main
$env:PRACTICE_ASSESSOR_MODE='rules'
$env:PRACTICE_WEB_ORIGINS='http://localhost:3001'
npm run dev
```

## 启动 Flutter 远程模式

已有 Flutter 页面进程不会自动获得新增的 `dart-define`，需要停止并重新启动：

```powershell
cd D:\dev\Uniprism\uniprism_app
flutter run -d chrome --web-hostname localhost --web-port 3001 `
  --dart-define=APP_ENV=development `
  --dart-define=ENABLE_DEVELOPER_TOOLS=true `
  --dart-define=API_BASE_URL=http://localhost:3000 `
  --dart-define=PRACTICE_ASSESSMENT_REMOTE=true
```

进入：`首页 → 开发者工具 → 练习评分实验室`。

页面顶部应显示“后端已连接”、会话 ID 和 `RULES`。若显示“演示 Mock”，说明没有传入 `PRACTICE_ASSESSMENT_REMOTE=true`。

## Mock 模式

不准备数据库时可先验证 UI 与本地规则：

```powershell
flutter run -d chrome --web-port 3001 `
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

因当前有两个 Flutter Chrome 开发实例运行，`flutter.bat` 可能等待启动锁。可以正常停止实例后运行标准命令：

```powershell
dart analyze lib/features/practice_assessment test/features/practice_assessment
flutter test test/features/practice_assessment test/widget_test.dart test/developer_tools_web_test.dart
```

本次已验证：练习模块静态分析无问题；练习模块 31 项测试通过；练习模块、开发者入口和 Widget 相关回归共 63 项通过。

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

# Task 4 Report：App 远程行为入口与交接文档

日期：2026-08-13

## 完成内容

- 收紧练习实验室的 Flutter 测试：Remote 工厂必须构造 `RemotePracticeRepository` 并暴露 remote connection mode；Mock 工厂保持 `MockGaokaoMathRepository` 与 mock mode。
- 补充远程 controller 的事件链特征测试：加载、答案变化、过程变化和提交会批量送入记录接口；测试断言事件类型、同一题目归属、长度分段载荷，并确认原始答案/过程文本不会作为事件载荷上传。
- 更新 `PRACTICE_ASSESSMENT_V1_HANDOFF.md`：
  - Flutter Web 固定使用 `flutter run -d chrome --web-port=5173 ...`；后端 `PRACTICE_WEB_ORIGINS` 同步为 `http://localhost:5173`。
  - 明确以顶部横幅识别 Remote（后端已连接）和 Mock（结果不会写入后端）。
  - 明确 App 可观察行为只进入后端 V1 API，V2 Shadow 仅在后端比对、不下发/不被 App 读取；管理端 benchmark 只使用模拟 Gold。

## 验证

- `git diff --check -- test/widget_test.dart test/features/practice_assessment/practice_session_controller_test.dart docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`：通过，无空白错误。
- `flutter test test/widget_test.dart test/features/practice_assessment/practice_session_controller_test.dart`：无输出，60 秒超时后停止。
- `flutter test test/features/practice_assessment/practice_session_controller_test.dart`：无输出，120 秒超时（exit code 124）。
- 未终止任何未知 Dart/Flutter 进程；超时后确认没有本任务启动的残留 child。由于测试运行器无法启动，未能完成新增特征测试的绿灯验证和受控变异运行。

## 已知限制

- Flutter 测试环境当前受既有长期 Dart 进程或启动锁阻塞；恢复可用环境后，应优先重跑上述两个单文件测试，再以移除 `updateAnswer` 的 `answerChanged` 记录为受控变异，确认事件链测试会失败，然后恢复实现并复跑。
- 本任务未修改生产行为：现有 Developer Tools 的编译时 Remote 选择、Remote repository 和事件 recorder 已满足要求；新增测试用于锁定该行为。

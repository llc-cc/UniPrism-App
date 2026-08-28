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

- 初次沙箱验证受 Flutter SDK lock 写权限阻塞；提升权限后的 fresh run 已取得绿灯。后续若再次出现无输出，应先检查 `D:\dev\flutter\bin\cache\flutter.bat.lock` 的写权限和已知 `flutter run` 状态，不能将启动重试误报为测试失败。
- 本任务未修改生产行为：现有 Developer Tools 的编译时 Remote 选择、Remote repository 和事件 recorder 已满足要求；新增测试用于锁定该行为。

## Fix round 1：验证证据更正

- Finding：交接文档将此前 38 项练习测试和 218 项全仓测试的基线记录表述为“本次已验证”，与本轮新增 Flutter 测试的超时记录相矛盾。
- 修正：自动验证章节已分离“此前基线验证记录”和“本轮 2026-08-13 验证状态”，明确本轮两条 Flutter 测试命令均未取得绿灯，且不再声称通过。
- 本轮命令与输出：`flutter test test/widget_test.dart test/features/practice_assessment/practice_session_controller_test.dart` 无输出，60 秒后停止；`flutter test test/features/practice_assessment/practice_session_controller_test.dart` 无输出，120 秒超时（exit code 124）；`git diff --check` 通过。
- 恢复步骤：正常停止已知的本项目 Flutter Web `flutter run`，重跑目标测试；仅在绿灯后重新以 `flutter run -d chrome --web-port=5173 ...` 启动 Web。
- Commit：`docs(practice): clarify verification evidence`。
- Concern（已解除）：当时尚未获得新增 Flutter 测试绿灯；后续提升权限后的 fresh run 已补齐证据。

## Verification follow-up：fresh green

- 根因：沙箱对 `D:\dev\flutter\bin\cache\flutter.bat.lock` 无写权限，Flutter batch 无限重试；此前 60 秒/120 秒超时是环境诊断历史，不是测试失败。
- `flutter test test/widget_test.dart test/features/practice_assessment/practice_session_controller_test.dart --reporter expanded`：44 项通过，exit 0，23.2 秒。
- `flutter test test/features/practice_assessment --reporter expanded`：39 项通过，exit 0，15.6 秒。
- `flutter analyze lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart`：`No issues found`，exit 0，32.4 秒。
- 执行顺序：停止已知的本项目 Web `flutter run`，完成上述测试和分析后，才重新启动 `flutter run -d chrome --web-port=5173 ...`。
- Commit：`docs(practice): record flutter verification evidence`。
- Concern：测试与分析已绿；本次只更新验证证据，没有修改测试或生产代码。

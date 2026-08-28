# 本地 Math AST 模型工具

这些脚本把 llama.cpp、Qwen 权重、缓存、日志和临时文件固定在
`D:\dev\local-ai\math-ast`，不会把模型写入仓库或 C 盘。

本机只有 Windows PowerShell 5.1，因此命令统一使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/math_ast/setup.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/math_ast/start.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/math_ast/stop.ps1
```

服务只监听 `127.0.0.1:8081`。`start.ps1` 会校验安装清单、模型哈希和
`llama-server.exe` 哈希；`stop.ps1` 只停止 PID 文件指向且映像路径完全匹配的进程。

运行脚本测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/math_ast/tests/paths.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/math_ast/tests/service.test.ps1
```

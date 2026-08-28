# SenseVoice 本地服务运行手册

## 适用范围

本手册用于 Windows 开发机上的本地 CPU SenseVoice 服务。运行时、模型、缓存、临时文件、录音和基准结果均位于 `D:\dev\local-ai\sensevoice`，服务只监听 `127.0.0.1`。

本地接口没有鉴权。不要把端口转发、代理或改绑到公网地址。应用适配层负责 5 MB 文件上限、15 秒音频上限和串行调用；直接请求 localhost 可以绕过这些客户端限制。任何公开部署都必须在服务器网关再次强制请求大小、音频时长、并发与限流，不能依赖客户端自律。

## 首次安装

从仓库根目录执行：

```powershell
pwsh -NoProfile -File tool/sensevoice/setup.ps1
```

若机器没有 `pwsh` 或 Python Launcher，但 `python` 指向可用的 Python 3，则使用 Windows PowerShell 5.1 的等价命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/sensevoice/setup.ps1 -PythonLauncher python
```

安装脚本会打印 C、D 盘安装前后的可用字节数，并在 C 盘净消耗超过 1 GB 时失败。版本锁文件写入 `D:\dev\local-ai\sensevoice\runtime\requirements.lock.txt`。

## 启动、检查与停止

启动前台服务：

```powershell
pwsh -NoProfile -File tool/sensevoice/start.ps1
```

没有 `pwsh` 时：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/sensevoice/start.ps1
```

真实生产命令由启动器构建为：

```text
D:\dev\local-ai\sensevoice\venv\Scripts\python.exe tool\sensevoice\server.py --host 127.0.0.1 --port 8000 --device cpu --model sensevoice --cors-origin http://localhost:5174
```

`server.py` 复用 FunASR 1.3.29 自带的 OpenAI 兼容应用，并补充浏览器 CORS 与稳定的 health 元数据。首次启动会从 ModelScope 下载 `iic/SenseVoiceSmall` 和 FSMN-VAD；等待日志出现 `Uvicorn running on http://127.0.0.1:8000` 后，再从第二个终端检查：

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

健康响应应包含 `status=healthy`、`runtime=funasr-1.3.29`、`device=cpu`、`model=sensevoice` 和已加载的 `sensevoice`。转写契约是：

- `POST http://127.0.0.1:8000/v1/audio/transcriptions`
- multipart 字段 `file`
- multipart 字段 `model=sensevoice`
- multipart 字段 `response_format=json`

在服务所在的前台终端按 `Ctrl+C` 停止。停止后再次请求 health 应连接失败；若仍能连接，应查找并终止占用 8000 端口的旧进程后再启动。

## 基准录音与运行

在 `D:\dev\local-ai\sensevoice\benchmarks\audio` 录制以下五个 PCM WAV 文件。朗读内容必须准确，不要把标点读入录音：

| 文件 | 朗读内容 |
|---|---|
| `01-polynomial.wav` | x的平方减三x加二 |
| `02-fraction.wav` | 根号下x加一整体除以x减一 |
| `03-relation.wav` | 零小于x并且x小于等于一 |
| `04-ambiguity.wav` | 负二的平方 |
| `05-function.wav` | 正弦x加余弦x |

服务健康后执行：

```powershell
pwsh -NoProfile -File tool/sensevoice/benchmark.ps1
```

Windows PowerShell 5.1 替代命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/sensevoice/benchmark.ps1
```

脚本会在任何 HTTP 请求前一次性列出缺失录音；随后请求一次 health，用第一条录音预热一次，再对五条录音各运行三次。音频时长从 PCM WAV 头读取，预热不计入统计。原始 JSON 写入 `D:\dev\local-ai\sensevoice\benchmarks\results\<UTC timestamp>.json`，控制台输出 elapsed time 和 RTF 的 median/P95。脚本只读取录音，不删除或覆盖 fixture。

## 磁盘检查

安装、模型更新或基准前后检查空间：

```powershell
Get-PSDrive C,D | Select-Object Name,Used,Free
```

若当前 PowerShell 的 `Free` 为空，使用：

```powershell
[IO.DriveInfo]::new('C:\') | Select-Object Name,AvailableFreeSpace
[IO.DriveInfo]::new('D:\') | Select-Object Name,AvailableFreeSpace
```

模型下载日志中的目标必须位于 `D:\dev\local-ai\sensevoice\cache\modelscope`。若出现 C 盘模型或临时文件路径，立即停止服务并检查启动是否经过 `start.ps1`。

## 故障恢复

### 8000 端口冲突

先确认旧进程是否仍是需要保留的服务。若端口确需避让，可临时启动到另一个回环端口：

```powershell
pwsh -NoProfile -File tool/sensevoice/start.ps1 -Port 8001
```

调用方和 benchmark 需要同步使用 `http://127.0.0.1:8001`。不要通过修改 host 来解决端口冲突。

### 模型下载失败

保留已下载的 D 盘缓存，确认网络和 D 盘空间后重新执行启动命令。ModelScope 会复用已有文件。不要把缓存迁移到 C 盘，也不要在下载未完成时把 health 失败误判为模型加载成功。

### 服务启动失败

先运行路径行为测试和无副作用配置验证：

```powershell
powershell.exe -NoProfile -File tool/sensevoice/tests/paths.test.ps1
powershell.exe -NoProfile -File tool/sensevoice/start.ps1 -ValidateOnly
```

若虚拟环境解释器缺失，重新运行 setup。若日志提示 ffmpeg 未安装，当前 PCM WAV 路径会回退到 torchaudio；本地基准不因此要求安装 ffmpeg。

# SenseVoice local runtime

```powershell
pwsh -NoProfile -File tool/sensevoice/setup.ps1
pwsh -NoProfile -File tool/sensevoice/start.ps1
pwsh -NoProfile -File tool/sensevoice/benchmark.ps1
```

Weights, caches, audio, and generated results are kept outside Git under
`D:\dev\local-ai\sensevoice`.

[CmdletBinding()]
param(
  [string] $Root = 'D:\dev\local-ai\sensevoice',
  [string] $PythonLauncher = 'py'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'SenseVoicePaths.psm1'
Import-Module $modulePath -Force
$paths = Get-SenseVoicePaths -Root $Root

$freeBefore = @{}
foreach ($driveName in @('C', 'D')) {
  $freeBefore[$driveName] = Get-SenseVoiceDriveFreeBytes -DriveName $driveName
  Write-Host ("{0}: free bytes before setup = {1}" -f $driveName, $freeBefore[$driveName])
}

$createdDirectories = @(
  $paths.Root,
  $paths.Runtime,
  $paths.Venv,
  $paths.Models,
  $paths.PipCache,
  $paths.ModelScopeCache,
  $paths.HuggingFaceCache,
  $paths.TorchCache,
  $paths.Temp,
  (Join-Path $paths.Temp 'pycache'),
  $paths.Benchmarks
)
foreach ($directory in $createdDirectories) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

Write-Host 'Created SenseVoice D-drive directories:'
$createdDirectories | ForEach-Object { Write-Host $_ }
Set-SenseVoiceProcessEnvironment -Paths $paths

# 依赖安装必须通过虚拟环境执行，确保全局 Python 与用户目录不会承载模型运行时资产.
& $PythonLauncher @('-3.11', '-m', 'venv', $paths.Venv)
if ($LASTEXITCODE -ne 0) {
  throw "Python virtual environment creation failed with exit code $LASTEXITCODE"
}

$python = Join-Path $paths.Venv 'Scripts\python.exe'
& $python @('-m', 'pip', 'install', '--upgrade', 'pip')
if ($LASTEXITCODE -ne 0) {
  throw "pip upgrade failed with exit code $LASTEXITCODE"
}

& $python @(
  '-m', 'pip', 'install',
  '--index-url', 'https://download.pytorch.org/whl/cpu',
  'torch', 'torchaudio'
)
if ($LASTEXITCODE -ne 0) {
  throw "CPU PyTorch installation failed with exit code $LASTEXITCODE"
}

$requirements = Join-Path $PSScriptRoot 'requirements.in'
& $python @('-m', 'pip', 'install', '-r', $requirements)
if ($LASTEXITCODE -ne 0) {
  throw "SenseVoice requirements installation failed with exit code $LASTEXITCODE"
}

& $python @('-c', 'import torch, funasr; print(torch.__version__); print(funasr.__version__)')
if ($LASTEXITCODE -ne 0) {
  throw "SenseVoice dependency import check failed with exit code $LASTEXITCODE"
}

$lockFile = Join-Path $paths.Runtime 'requirements.lock.txt'
$freeze = & $python @('-m', 'pip', 'freeze')
if ($LASTEXITCODE -ne 0) {
  throw "pip freeze failed with exit code $LASTEXITCODE"
}
$freeze | Set-Content -Path $lockFile -Encoding utf8

$freeAfter = @{}
foreach ($driveName in @('C', 'D')) {
  $freeAfter[$driveName] = Get-SenseVoiceDriveFreeBytes -DriveName $driveName
  Write-Host ("{0}: free bytes after setup = {1}" -f $driveName, $freeAfter[$driveName])
}

Assert-SenseVoiceCDriveUsage -FreeBytesBefore $freeBefore['C'] -FreeBytesAfter $freeAfter['C']

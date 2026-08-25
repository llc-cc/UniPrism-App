$ErrorActionPreference = 'Stop'

$module = Join-Path $PSScriptRoot '..\SenseVoicePaths.psm1'
Import-Module $module -Force

$paths = Get-SenseVoicePaths -Root 'D:\dev\local-ai\sensevoice'
if ($paths.Root -ne 'D:\dev\local-ai\sensevoice') { throw 'Root mismatch' }
$rootBoundary = "$($paths.Root.TrimEnd('\'))\"
foreach ($property in @(
  'Runtime', 'Venv', 'Models', 'PipCache', 'ModelScopeCache',
  'HuggingFaceCache', 'TorchCache', 'Temp', 'Benchmarks'
)) {
  $value = [string]$paths.$property
  if (-not $value.StartsWith($rootBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$property escaped the D-drive root: $value"
  }
}

$prefixCollisionPath = "$($paths.Root)-escape\runtime"
if ($prefixCollisionPath.StartsWith($rootBoundary, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Directory boundary accepted prefix collision: $prefixCollisionPath"
}

try {
  Get-SenseVoicePaths -Root 'C:\sensevoice' | Out-Null
  throw 'C-drive root should have been rejected'
} catch {
  if ($_.Exception.Message -eq 'C-drive root should have been rejected') { throw }
}

Set-SenseVoiceProcessEnvironment -Paths $paths
if ($env:PIP_CACHE_DIR -ne $paths.PipCache) { throw 'PIP cache mismatch' }
if ($env:MODELSCOPE_CACHE -ne $paths.ModelScopeCache) { throw 'ModelScope cache mismatch' }
if ($env:HF_HOME -ne $paths.HuggingFaceCache) { throw 'HF cache mismatch' }
if ($env:TORCH_HOME -ne $paths.TorchCache) { throw 'Torch cache mismatch' }
if ($env:TEMP -ne $paths.Temp -or $env:TMP -ne $paths.Temp) {
  throw 'Temporary directory mismatch'
}

$cDriveFreeBytes = Get-SenseVoiceDriveFreeBytes -DriveName 'C'
if ($cDriveFreeBytes -le 0) { throw 'C-drive free space was not readable' }

try {
  Get-SenseVoiceDriveFreeBytes -DriveName '?' | Out-Null
  throw 'Unreadable drive should have been rejected'
} catch {
  if ($_.Exception.Message -eq 'Unreadable drive should have been rejected') { throw }
}

try {
  Assert-SenseVoiceCDriveUsage -FreeBytesBefore 2GB -FreeBytesAfter (1GB - 1)
  throw 'C-drive usage above 1GB should have been rejected'
} catch {
  if ($_.Exception.Message -eq 'C-drive usage above 1GB should have been rejected') { throw }
}

Assert-SenseVoiceCDriveUsage -FreeBytesBefore 2GB -FreeBytesAfter 1GB

# 配置验证模式必须执行生产参数构建逻辑，同时避免在自动化测试中加载模型或占用端口.
$startScriptPath = Join-Path $PSScriptRoot '..\start.ps1'
$startConfiguration = & $startScriptPath -ValidateOnly | ConvertFrom-Json
if ($startConfiguration.host -ne '127.0.0.1') {
  throw "SenseVoice must bind to loopback only, got: $($startConfiguration.host)"
}
if ($startConfiguration.host -eq '0.0.0.0') {
  throw 'Public bind is forbidden for local development'
}
if ($startConfiguration.device -ne 'cpu') {
  throw "The primary laptop runtime must use CPU, got: $($startConfiguration.device)"
}

$emptyAudioDirectory = Join-Path $PSScriptRoot '.empty-audio'
New-Item -ItemType Directory -Force -Path $emptyAudioDirectory | Out-Null
try {
  & (Join-Path $PSScriptRoot '..\benchmark.ps1') `
    -AudioDirectory $emptyAudioDirectory `
    -ServiceBaseUri 'http://127.0.0.1:1'
  throw 'Benchmark should reject missing audio fixtures'
} catch {
  if ($_.Exception.Message -eq 'Benchmark should reject missing audio fixtures') { throw }
  foreach ($missingFile in @(
    '01-polynomial.wav',
    '02-fraction.wav',
    '03-relation.wav',
    '04-ambiguity.wav',
    '05-function.wav'
  )) {
    if ($_.Exception.Message -notlike "*$missingFile*") {
      throw "Missing fixture error omitted $missingFile`: $($_.Exception.Message)"
    }
  }
} finally {
  Remove-Item -LiteralPath $emptyAudioDirectory -Force
}

$setupConfiguration = & (Join-Path $PSScriptRoot '..\setup.ps1') `
  -PythonLauncher 'python' `
  -ValidateOnly | ConvertFrom-Json
if (($setupConfiguration.venvArguments -join ' ') -ne '-m venv D:\dev\local-ai\sensevoice\venv') {
  throw "Direct Python launcher received invalid venv arguments: $($setupConfiguration.venvArguments -join ' ')"
}

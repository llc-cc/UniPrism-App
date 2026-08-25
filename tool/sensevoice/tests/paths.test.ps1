$ErrorActionPreference = 'Stop'

$module = Join-Path $PSScriptRoot '..\SenseVoicePaths.psm1'
Import-Module $module -Force

$paths = Get-SenseVoicePaths -Root 'D:\dev\local-ai\sensevoice'
if ($paths.Root -ne 'D:\dev\local-ai\sensevoice') { throw 'Root mismatch' }
foreach ($property in @(
  'Runtime', 'Venv', 'Models', 'PipCache', 'ModelScopeCache',
  'HuggingFaceCache', 'TorchCache', 'Temp', 'Benchmarks'
)) {
  $value = [string]$paths.$property
  if (-not $value.StartsWith($paths.Root, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$property escaped the D-drive root: $value"
  }
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

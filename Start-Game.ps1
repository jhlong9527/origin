$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
$enginePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $enginePath)) {
    throw 'Godot executable was not found beside the project directory.'
}
Start-Process -FilePath $enginePath -ArgumentList @('--path', ('"' + $projectPath + '"')) -WorkingDirectory $projectPath


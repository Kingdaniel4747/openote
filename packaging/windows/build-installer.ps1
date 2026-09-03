param([Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)
$ErrorActionPreference = 'Stop'
$taskRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$taskRelease = Join-Path $taskRepo 'app\build\windows\x64\runner\Release'
$taskStage = Join-Path $taskRepo "installer-stage-$Version"

foreach ($name in @('openote.exe', 'flutter_windows.dll', 'sqlite3.dll', 'libmpv-2.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskRelease $name))) {
        throw "Incomplete Windows build: $name is missing"
    }
}
# A fresh staging folder cannot accidentally package an old DLL from a prior run.
New-Item -ItemType Directory -Path $taskStage | Out-Null
Get-ChildItem -LiteralPath $taskRelease -Force | Copy-Item -Destination $taskStage -Recurse
Copy-Item -LiteralPath (Join-Path $taskRepo 'rust\onote_core\target\release\onote_core.dll') -Destination $taskStage -Force
Copy-Item -LiteralPath (Join-Path $taskRepo 'LICENSE') -Destination $taskStage

# App-local redistributables: the laptop needs neither Visual Studio nor a
# separate administrator-only VC++ runtime installation.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio locator is missing' }
$vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vsPath) { throw 'MSVC build tools are missing' }
$redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
$crt = Get-ChildItem -LiteralPath $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object {
        Get-ChildItem -Path (Join-Path $_.FullName 'x64') -Filter 'Microsoft.VC*.CRT' -Directory -ErrorAction SilentlyContinue
    } | Select-Object -First 1
if (-not $crt) { throw 'Redistributable x64 C++ runtime is missing' }
Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' -File | Copy-Item -Destination $taskStage -Force
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskStage $name))) { throw "Missing runtime: $name" }
}

$roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }
$iscc = Get-ChildItem -Path $roots -Filter 'Inno Setup*' -Directory |
    ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Sort-Object { if ($_ -match 'Inno Setup\s+(\d+)') { [int]$Matches[1] } else { 0 } } |
    Select-Object -Last 1
if (-not $iscc) { throw 'Inno Setup compiler was not found' }
& $iscc "/DAppVersion=$Version" "/DStageDir=$taskStage" (Join-Path $PSScriptRoot 'openote.iss')
if ($LASTEXITCODE -ne 0) { throw "Installer compiler failed: $LASTEXITCODE" }
$installer = Join-Path $PSScriptRoot "openote-$Version-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'Compiler produced no setup EXE' }
Copy-Item -LiteralPath $installer -Destination $taskRepo -Force
Get-Item -LiteralPath (Join-Path $taskRepo "openote-$Version-windows-x64-setup.exe") |
    Select-Object Name, Length

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$probeRoot = Join-Path $projectRoot 'build/resolve-symlinks-test'
$hidden = Join-Path $probeRoot '[AppData]'
$leaf = Join-Path $hidden 'Local/Cache'
[IO.Directory]::CreateDirectory($leaf) | Out-Null
$directory = Get-Item -LiteralPath $hidden -Force
$directory.Attributes = $directory.Attributes -bor [IO.FileAttributes]::Hidden
$resolver = Join-Path $projectRoot 'third_party/super_native_extensions/cargokit/cmake/resolve_symlinks.ps1'
$expected = $leaf.Replace('\', '/')
$result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver $expected 2>&1
if ($LASTEXITCODE -ne 0 -or "$result".Trim() -ne $expected) {
    throw "Resolver failed for hidden/literal path: $result"
}
Write-Host 'PASS: Windows PowerShell resolves hidden path components and literal brackets.'

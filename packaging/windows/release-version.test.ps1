$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release-version.ps1')
$cases = @(
    @{ Base = '0.8.0'; Tags = @(); Want = '0.8.1' },
    @{ Base = '0.8.0'; Tags = @('v0.8.2','v0.8.10','not-a-version','v99.0.0-beta'); Want = '0.8.11' },
    @{ Base = '1.0.0'; Tags = @('v0.9.9'); Want = '1.0.1' },
    @{ Base = '0.8.0'; Tags = @('v1.2.65535'); Want = '1.3.0' },
    @{ Base = '0.8.0'; Tags = @('v1.65535.65535'); Want = '2.0.0' }
)
foreach ($case in $cases) {
    $got = Get-NextOpenoteVersion -Baseline $case.Base -Tags $case.Tags
    if ($got -ne $case.Want) { throw "Version test failed: $got vs $($case.Want)" }
}
Write-Output 'All 5 release-version tests passed.'

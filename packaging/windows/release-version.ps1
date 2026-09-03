# Pure version calculation, also used by release-version.test.ps1.
function Get-NextOpenoteVersion {
    param([string]$Baseline, [string[]]$Tags)
    if ($Baseline -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid baseline version' }
    $highest = [version]$Baseline
    foreach ($tag in $Tags) {
        if ($tag -match '^v?(\d+\.\d+\.\d+)$') {
            $candidate = [version]$Matches[1]
            if ($candidate -gt $highest) { $highest = $candidate }
        }
    }
    # Windows executable version components are unsigned 16-bit numbers.
    $major = $highest.Major; $minor = $highest.Minor; $patch = $highest.Build + 1
    if ($patch -gt 65535) { $patch = 0; $minor++ }
    if ($minor -gt 65535) { $minor = 0; $major++ }
    if ($major -gt 65535) { throw 'Windows version range exhausted' }
    return "$major.$minor.$patch"
}

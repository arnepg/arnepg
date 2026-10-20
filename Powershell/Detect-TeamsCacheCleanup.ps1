# Intune Win32 detection script.
# Run this detection in the logged-on user's context using 64-bit PowerShell.
# The app is considered detected for 15 minutes after a run. After that, it
# becomes available for the user to run again in Company Portal.

$markerFile = Join-Path $env:LOCALAPPDATA 'Company\TeamsCacheCleanup\LastRun.txt'
if (-not (Test-Path -LiteralPath $markerFile -PathType Leaf)) {
    exit 1
}

try {
    $raw = (Get-Content -LiteralPath $markerFile -Raw -ErrorAction Stop).Trim()
    $lastRun = [datetime]::MinValue
    if (-not [datetime]::TryParse($raw, [ref]$lastRun)) {
        exit 1
    }

    if (((Get-Date) - $lastRun).TotalMinutes -le 15 -and $lastRun -le (Get-Date).AddMinutes(1)) {
        Write-Output 'Teams cache cleanup recently completed.'
        exit 0
    }

    exit 1
}
catch {
    exit 1
}

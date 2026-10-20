#requires -Version 5.1
<#
.SYNOPSIS
    User-initiated Microsoft Teams cache cleanup for Intune Company Portal.
.DESCRIPTION
    Run in the logged-on user's context. Supports new Teams and classic Teams.
    Logs to %LOCALAPPDATA%\Company\Logs\TeamsCacheCleanup.log.
    Creates a short-lived marker for Intune detection so the available app can
    be run again after the marker expires.
#>

$ErrorActionPreference = 'Stop'
$LogDirectory = Join-Path $env:LOCALAPPDATA 'Company\Logs'
$LogFile = Join-Path $LogDirectory 'TeamsCacheCleanup.log'
$MarkerDirectory = Join-Path $env:LOCALAPPDATA 'Company\TeamsCacheCleanup'
$MarkerFile = Join-Path $MarkerDirectory 'LastRun.txt'

try {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    New-Item -Path $MarkerDirectory -ItemType Directory -Force | Out-Null
} catch {
    Write-Error "Unable to create user log/marker directories: $($_.Exception.Message)"
    exit 1
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $LogFile -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

$hadErrors = $false
try {
    Write-Log '===== Teams cache cleanup started ====='
    Write-Log "User: $env:USERDOMAIN\$env:USERNAME"
    Write-Log "PowerShell: $($PSVersionTable.PSVersion)"

    # Close Teams processes belonging to the current user session.
    $processNames = @('ms-teams', 'Teams', 'msteams_autostarter')
    foreach ($name in $processNames) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            try {
                Write-Log "Stopping process $($process.ProcessName), PID $($process.Id)"
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            } catch {
                $hadErrors = $true
                Write-Log "Could not stop $name (PID $($process.Id)): $($_.Exception.Message)" 'WARN'
            }
        }
    }

    # Allow process handles to close before deleting cache files.
    Start-Sleep -Seconds 3
    $stillRunning = Get-Process -Name @('ms-teams','Teams') -ErrorAction SilentlyContinue
    if ($stillRunning) {
        Write-Log 'One or more Teams processes remain running; some files may be locked.' 'WARN'
    }

    # Cache locations. Only contents of these known cache directories are removed.
    $cachePaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'),
        (Join-Path $env:APPDATA 'Microsoft\Teams')
    )

    $foundCache = $false
    foreach ($cachePath in $cachePaths) {
        if (-not (Test-Path -LiteralPath $cachePath -PathType Container)) {
            Write-Log "Cache path not present: $cachePath"
            continue
        }

        $foundCache = $true
        Write-Log "Cleaning cache contents: $cachePath"
        try {
            Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction Stop |
                ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                        Write-Log "Removed: $($_.FullName)"
                    } catch {
                        $hadErrors = $true
                        Write-Log "Could not remove $($_.FullName): $($_.Exception.Message)" 'WARN'
                    }
                }
        } catch {
            $hadErrors = $true
            Write-Log "Could not enumerate $cachePath : $($_.Exception.Message)" 'WARN'
        }
    }

    if (-not $foundCache) {
        Write-Log 'No supported Teams cache directory was found. This can be normal if Teams is not installed or has not been launched.' 'WARN'
    }

    # Restart Teams. Prefer the registered new Teams protocol.
    $teamsStarted = $false
    try {
        Start-Process -FilePath 'msteams:'
        Start-Sleep -Seconds 5
        if (Get-Process -Name 'ms-teams' -ErrorAction SilentlyContinue) {
            $teamsStarted = $true
            Write-Log 'New Teams launched using the msteams: protocol.'
        } else {
            Write-Log 'Protocol launch was requested, but ms-teams process was not detected yet.' 'WARN'
        }
    } catch {
        Write-Log "New Teams protocol launch failed: $($_.Exception.Message)" 'WARN'
    }

    if (-not $teamsStarted) {
        $classicPaths = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft Teams\current\Teams.exe')
        )
        foreach ($teamsPath in $classicPaths) {
            if (Test-Path -LiteralPath $teamsPath -PathType Leaf) {
                try {
                    Start-Process -FilePath $teamsPath
                    $teamsStarted = $true
                    Write-Log "Classic Teams launch requested: $teamsPath"
                    break
                } catch {
                    Write-Log "Could not launch $teamsPath : $($_.Exception.Message)" 'WARN'
                }
            }
        }
    }

    if (-not $teamsStarted) {
        Write-Log 'Could not confirm Teams startup. User can launch Teams manually.' 'WARN'
    }

    # Write marker only after the cleanup sequence completed.
    # Detection treats this app as installed for 15 minutes, then permits rerun.
    Set-Content -LiteralPath $MarkerFile -Value (Get-Date).ToString('o') -Encoding UTF8
    Write-Log "Run marker updated: $MarkerFile"
    Write-Log "===== Teams cache cleanup finished; warnings/errors: $hadErrors ====="

    # Return success if the sequence ran; locked cache files are logged as warnings.
    exit 0
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
    exit 1
}

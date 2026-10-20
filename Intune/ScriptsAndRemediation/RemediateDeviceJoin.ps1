# ============================================================
# Intune Remediation - Azure AD / PRT Recovery
# ============================================================
#
# Designed for:
#   - Microsoft Intune Remediations
#   - Run using logged-on credentials = YES
#   - 64-bit PowerShell = YES
#
# Purpose:
#   1. Check current Azure AD / Domain Join / PRT state
#   2. Run dsregcmd /forcerecovery as the logged-on user
#   3. Re-check PRT
#   4. If PRT is still missing:
#        - Create temporary SYSTEM scheduled task
#        - Run Automatic-Device-Join as SYSTEM
#        - Remove temporary task
#   5. Verify final state
#
# IMPORTANT:
#   - This version does NOT automatically run dsregcmd /leave.
#   - /leave should be a separate, controlled recovery step.
#
# Log:
#   C:\Temp\Logs\AAD-JoinError.log
#
# ============================================================

$LogPath = "C:\Temp\Logs\AAD-JoinError.log"

$LogDirectory = Split-Path $LogPath -Parent

if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Computer = $env:COMPUTERNAME

    $Line = "$Timestamp [$Level] [$Computer] $Message"

    Add-Content -Path $LogPath -Value $Line -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------
# 1. Locate dsregcmd.exe
# ------------------------------------------------------------

$DsregCmd = $null

if (Test-Path "C:\Windows\System32\dsregcmd.exe") {
    $DsregCmd = "C:\Windows\System32\dsregcmd.exe"
}
elseif (Test-Path "C:\Windows\Sysnative\dsregcmd.exe") {
    $DsregCmd = "C:\Windows\Sysnative\dsregcmd.exe"
}

if (-not $DsregCmd) {
    Write-Log "dsregcmd.exe could not be found." "ERROR"
    exit 1
}

Write-Log "Using dsregcmd: $DsregCmd"

# ------------------------------------------------------------
# 2. Function: Get dsregcmd status
# ------------------------------------------------------------

function Get-DsregStatus {

    try {

        $Output = & $DsregCmd /status 2>&1

        if (-not $Output) {
            Write-Log "dsregcmd /status returned no output." "ERROR"
            return $null
        }

        $Result = [ordered]@{
            AzureAdJoined = ""
            DomainJoined  = ""
            AzureAdPrt    = ""
            DeviceId      = ""
            AttemptStatus = ""
            ServerError   = ""
            ServerErrorDescription = ""
        }

        foreach ($Line in $Output) {

            $Text = $Line.ToString().Trim()

            if ($Text -match '^AzureAdJoined\s*:\s*(.*)$') {
                $Result.AzureAdJoined = $Matches[1].Trim()
            }

            elseif ($Text -match '^DomainJoined\s*:\s*(.*)$') {
                $Result.DomainJoined = $Matches[1].Trim()
            }

            elseif ($Text -match '^AzureAdPrt\s*:\s*(.*)$') {
                $Result.AzureAdPrt = $Matches[1].Trim()
            }

            elseif ($Text -match '^DeviceId\s*:\s*(.*)$') {
                $Result.DeviceId = $Matches[1].Trim()
            }

            elseif ($Text -match '^Attempt Status\s*:\s*(.*)$') {
                $Result.AttemptStatus = $Matches[1].Trim()
            }

            elseif ($Text -match '^Server Error Code\s*:\s*(.*)$') {
                $Result.ServerError = $Matches[1].Trim()
            }

            elseif ($Text -match '^Server Error Description\s*:\s*(.*)$') {
                $Result.ServerErrorDescription = $Matches[1].Trim()
            }
        }

        return [PSCustomObject]$Result
    }
    catch {
        Write-Log "Failed to execute dsregcmd /status: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ------------------------------------------------------------
# 3. Initial state
# ------------------------------------------------------------

Write-Log "============================================================"
Write-Log "Starting Azure AD / PRT recovery"
Write-Log "Running user: $env:USERDOMAIN\$env:USERNAME"

$Initial = Get-DsregStatus

if (-not $Initial) {
    Write-Log "Unable to determine device state." "ERROR"
    exit 1
}

Write-Log "Initial AzureAdJoined: $($Initial.AzureAdJoined)"
Write-Log "Initial DomainJoined : $($Initial.DomainJoined)"
Write-Log "Initial AzureAdPrt   : $($Initial.AzureAdPrt)"

if ($Initial.DeviceId) {
    Write-Log "DeviceId: $($Initial.DeviceId)"
}

if ($Initial.AttemptStatus) {
    Write-Log "Previous Attempt Status: $($Initial.AttemptStatus)"
}

if ($Initial.ServerError) {
    Write-Log "Previous Server Error: $($Initial.ServerError)"
}

if ($Initial.ServerErrorDescription) {
    Write-Log "Previous Server Error Description: $($Initial.ServerErrorDescription)"
}

# ------------------------------------------------------------
# 4. Already healthy?
# ------------------------------------------------------------

if (
    $Initial.AzureAdJoined -eq "YES" -and
    $Initial.DomainJoined  -eq "YES" -and
    $Initial.AzureAdPrt    -eq "YES"
) {

    Write-Log "Device is healthy. Azure AD joined, Domain joined and PRT available."

    exit 0
}

# ------------------------------------------------------------
# 5. Validate expected hybrid-joined state
# ------------------------------------------------------------

if (
    $Initial.AzureAdJoined -ne "YES" -or
    $Initial.DomainJoined  -ne "YES"
) {

    Write-Log "Device is not in expected hybrid-joined state." "WARN"
    Write-Log "No automatic recovery will be attempted."

    exit 0
}

# ------------------------------------------------------------
# 6. Run dsregcmd /forcerecovery
# ------------------------------------------------------------

if ($Initial.AzureAdPrt -ne "YES") {

    Write-Log "AzureAdPrt is not available."
    Write-Log "Running dsregcmd /forcerecovery as logged-on user."

    try {

        $RecoveryOutput = & $DsregCmd /forcerecovery 2>&1

        foreach ($Line in $RecoveryOutput) {
            if ($Line -and $Line.ToString().Trim()) {
                Write-Log "forcerecovery: $($Line.ToString().Trim())"
            }
        }

        Write-Log "dsregcmd /forcerecovery completed."

    }
    catch {
        Write-Log "dsregcmd /forcerecovery failed: $($_.Exception.Message)" "ERROR"
    }
}

# ------------------------------------------------------------
# 7. Wait for recovery
# ------------------------------------------------------------

Write-Log "Waiting 60 seconds for PRT recovery."

Start-Sleep -Seconds 60

# ------------------------------------------------------------
# 8. Check PRT again
# ------------------------------------------------------------

$AfterRecovery = Get-DsregStatus

if (-not $AfterRecovery) {
    Write-Log "Unable to check device state after forcerecovery." "ERROR"
    exit 1
}

Write-Log "After forcerecovery:"
Write-Log "AzureAdJoined: $($AfterRecovery.AzureAdJoined)"
Write-Log "DomainJoined : $($AfterRecovery.DomainJoined)"
Write-Log "AzureAdPrt   : $($AfterRecovery.AzureAdPrt)"

# ------------------------------------------------------------
# 9. PRT recovered
# ------------------------------------------------------------

if ($AfterRecovery.AzureAdPrt -eq "YES") {

    Write-Log "SUCCESS: AzureAdPrt is now YES."
    Write-Log "No device re-registration was required."

    exit 0
}

# ------------------------------------------------------------
# 10. PRT still missing
# ------------------------------------------------------------

Write-Log "AzureAdPrt is still NO after forcerecovery." "WARN"
Write-Log "A SYSTEM task will now trigger Automatic-Device-Join."

# ------------------------------------------------------------
# 11. Create temporary SYSTEM scheduled task
# ------------------------------------------------------------

$TempTaskName = "Intune-AAD-Recovery-$([guid]::NewGuid().ToString())"

$TaskPath = "\"

try {

    $Action = New-ScheduledTaskAction `
        -Execute "C:\Windows\System32\schtasks.exe" `
        -Argument '/Run /TN "\Microsoft\Windows\Workplace Join\Automatic-Device-Join"'

    $Principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $Trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1)

    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $TempTaskName `
        -TaskPath $TaskPath `
        -Action $Action `
        -Principal $Principal `
        -Trigger $Trigger `
        -Settings $Settings `
        -Force `
        -ErrorAction Stop | Out-Null

    Write-Log "Temporary SYSTEM recovery task created: $TempTaskName"

}
catch {

    Write-Log "Failed to create temporary SYSTEM task: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ------------------------------------------------------------
# 12. Start temporary SYSTEM task
# ------------------------------------------------------------

try {

    Start-ScheduledTask `
        -TaskName $TempTaskName `
        -TaskPath $TaskPath `
        -ErrorAction Stop

    Write-Log "Temporary SYSTEM recovery task started."

}
catch {

    Write-Log "Failed to start temporary SYSTEM recovery task: $($_.Exception.Message)" "ERROR"

    Unregister-ScheduledTask `
        -TaskName $TempTaskName `
        -TaskPath $TaskPath `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    exit 1
}

# ------------------------------------------------------------
# 13. Wait for Automatic-Device-Join
# ------------------------------------------------------------

Write-Log "Waiting 120 seconds for Automatic-Device-Join."

Start-Sleep -Seconds 120

# ------------------------------------------------------------
# 14. Remove temporary task
# ------------------------------------------------------------

try {

    Unregister-ScheduledTask `
        -TaskName $TempTaskName `
        -TaskPath $TaskPath `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Write-Log "Temporary SYSTEM recovery task removed."

}
catch {

    Write-Log "Could not remove temporary task: $TempTaskName" "WARN"
}

# ------------------------------------------------------------
# 15. Final status
# ------------------------------------------------------------

$Final = Get-DsregStatus

if (-not $Final) {

    Write-Log "Unable to determine final device state." "ERROR"
    exit 1
}

Write-Log "Final device state:"
Write-Log "AzureAdJoined: $($Final.AzureAdJoined)"
Write-Log "DomainJoined : $($Final.DomainJoined)"
Write-Log "AzureAdPrt   : $($Final.AzureAdPrt)"

if ($Final.ServerError) {
    Write-Log "Final Server Error: $($Final.ServerError)"
}

if ($Final.ServerErrorDescription) {
    Write-Log "Final Server Error Description: $($Final.ServerErrorDescription)"
}

# ------------------------------------------------------------
# 16. Final result
# ------------------------------------------------------------

if (
    $Final.AzureAdJoined -eq "YES" -and
    $Final.DomainJoined  -eq "YES" -and
    $Final.AzureAdPrt    -eq "YES"
) {

    Write-Log "SUCCESS: Azure AD Join and PRT are healthy."

    exit 0
}

Write-Log "Recovery did not restore AzureAdPrt." "WARN"
Write-Log "No dsregcmd /leave was performed."

exit 1
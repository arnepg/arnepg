# ============================================================
# Intune Remediation - Disk Cleanup
#
# Purpose:
#   Automatically clean up C: when free disk space is
#   below 10%.
#
# Designed for:
#   Microsoft Intune Remediations
#   SYSTEM context
#
# Log:
#   C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#   DiskCleanupRemediation.log
# NOTES
#    FileName:    RemediateDiskSpace.ps1
#    Author:      Arne P Groenmo
#    Created:     2026-10-05
#    Updated:     
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$DriveLetter = "C:"
$MinimumFreePercent = 10

$LogDirectory = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogDirectory "DiskCleanupRemediation.log"


# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO","WARNING","ERROR")]
        [string]$Level = "INFO"
    )

    try {
        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $LogMessage = "$Timestamp [$Level] $Message"

        Add-Content -Path $LogFile -Value $LogMessage -Encoding UTF8
    }
    catch {
        # Do not allow logging errors to stop remediation
    }
}


# ------------------------------------------------------------
# Get disk information
# ------------------------------------------------------------

function Get-DiskInformation {

    try {

        $Disk = Get-CimInstance -ClassName Win32_LogicalDisk `
            -Filter "DeviceID='$DriveLetter'" `
            -ErrorAction Stop

        if (-not $Disk) {
            throw "Drive $DriveLetter could not be found."
        }

        if ($Disk.Size -le 0) {
            throw "Invalid disk size detected."
        }

        $TotalBytes = [double]$Disk.Size
        $FreeBytes  = [double]$Disk.FreeSpace

        $FreePercent = ($FreeBytes / $TotalBytes) * 100

        [PSCustomObject]@{
            TotalBytes  = $TotalBytes
            FreeBytes   = $FreeBytes
            TotalGB     = [math]::Round($TotalBytes / 1GB, 2)
            FreeGB      = [math]::Round($FreeBytes / 1GB, 2)
            FreePercent = [math]::Round($FreePercent, 2)
        }

    }
    catch {
        Write-Log "Unable to get disk information: $($_.Exception.Message)" "ERROR"
        return $null
    }
}


# ------------------------------------------------------------
# Cleanup Windows Temp
# ------------------------------------------------------------

function Clear-TempFolder {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Log "Temp path does not exist: $Path"
        return
    }

    Write-Log "Cleaning: $Path"

    try {

        Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    }
    catch {
        Write-Log "Some files could not be removed from $Path : $($_.Exception.Message)" "WARNING"
    }
}


# ------------------------------------------------------------
# Cleanup Recycle Bin
# ------------------------------------------------------------

function Clear-RecycleBinSafe {

    Write-Log "Cleaning Recycle Bin"

    try {

        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        Write-Log "Recycle Bin cleanup completed"

    }
    catch {
        Write-Log "Recycle Bin cleanup failed: $($_.Exception.Message)" "WARNING"
    }
}


# ------------------------------------------------------------
# Remove Windows.old
# ------------------------------------------------------------

function Remove-WindowsOld {

    $WindowsOldPath = "C:\Windows.old"

    if (-not (Test-Path $WindowsOldPath)) {
        Write-Log "Windows.old not found - nothing to remove."
        return
    }

    Write-Log "Windows.old found. Starting cleanup."

    try {

        # Take ownership and grant SYSTEM full access
        & takeown.exe /F $WindowsOldPath /R /D Y 2>&1 |
            Out-Null

        & icacls.exe $WindowsOldPath /grant SYSTEM:F /T /C 2>&1 |
            Out-Null

        # Remove Windows.old
        Remove-Item `
            -Path $WindowsOldPath `
            -Recurse `
            -Force `
            -ErrorAction Stop

        if (-not (Test-Path $WindowsOldPath)) {

            Write-Log "Windows.old successfully removed."

        }
        else {

            Write-Log "Windows.old still exists after cleanup." "WARNING"
        }

    }
    catch {

        Write-Log "Failed to remove Windows.old: $($_.Exception.Message)" "WARNING"
    }
}

# ------------------------------------------------------------
# Cleanup Windows Update Download Cache
# ------------------------------------------------------------

function Clear-WindowsUpdateCache {

    $UpdateCache = "C:\Windows\SoftwareDistribution\Download"

    if (-not (Test-Path $UpdateCache)) {
        return
    }

    Write-Log "Cleaning Windows Update download cache"

    try {

        $Service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue

        if ($Service -and $Service.Status -eq "Running") {

            Write-Log "Stopping Windows Update service"

            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

            Start-Sleep -Seconds 2
        }

        Get-ChildItem -Path $UpdateCache -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        if ($Service -and $Service.StartType -ne "Disabled") {

            Start-Service -Name wuauserv -ErrorAction SilentlyContinue

        }

        Write-Log "Windows Update cache cleanup completed"

    }
    catch {

        Write-Log "Windows Update cache cleanup failed: $($_.Exception.Message)" "WARNING"

        try {
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }
        catch {}
    }
}


# ------------------------------------------------------------
# Cleanup Delivery Optimization cache
# ------------------------------------------------------------

function Clear-DeliveryOptimization {

    $DOPath = "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"

    if (-not (Test-Path $DOPath)) {
        return
    }

    Write-Log "Cleaning Delivery Optimization cache"

    try {

        Get-ChildItem -Path $DOPath -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log "Delivery Optimization cleanup completed"

    }
    catch {
        Write-Log "Delivery Optimization cleanup encountered errors: $($_.Exception.Message)" "WARNING"
    }
}


# ------------------------------------------------------------
# Cleanup Windows Error Reporting
# ------------------------------------------------------------

function Clear-WindowsErrorReporting {

    $WERPaths = @(
        "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",
        "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"
    )

    foreach ($Path in $WERPaths) {

        if (Test-Path $Path) {

            Write-Log "Cleaning Windows Error Reporting: $Path"

            try {

                Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            }
            catch {

                Write-Log "Could not completely clean $Path" "WARNING"
            }
        }
    }
}


# ------------------------------------------------------------
# DISM Component Store Cleanup
# ------------------------------------------------------------

function Invoke-ComponentCleanup {

    Write-Log "Starting DISM Component Store cleanup"

    try {

        $Process = Start-Process `
            -FilePath "DISM.exe" `
            -ArgumentList "/Online","/Cleanup-Image","/StartComponentCleanup" `
            -Wait `
            -PassThru `
            -WindowStyle Hidden

        Write-Log "DISM finished with exit code $($Process.ExitCode)"

        if ($Process.ExitCode -ne 0) {
            Write-Log "DISM returned a non-zero exit code" "WARNING"
        }

    }
    catch {

        Write-Log "DISM cleanup failed: $($_.Exception.Message)" "WARNING"
    }
}


# ============================================================
# MAIN
# ============================================================

Write-Log "============================================================"
Write-Log "Starting disk cleanup remediation"
Write-Log "============================================================"


# ------------------------------------------------------------
# Get initial disk state
# ------------------------------------------------------------

$Before = Get-DiskInformation

if (-not $Before) {

    Write-Log "Unable to determine disk space. Remediation aborted." "ERROR"

    exit 1
}


Write-Log "Disk: $DriveLetter"
Write-Log "Total space: $($Before.TotalGB) GB"
Write-Log "Free space: $($Before.FreeGB) GB"
Write-Log "Free space: $($Before.FreePercent) %"


# ------------------------------------------------------------
# Check threshold
# ------------------------------------------------------------

if ($Before.FreePercent -ge $MinimumFreePercent) {

    Write-Log "Disk space is OK. No cleanup required."
    Write-Log "Threshold: $MinimumFreePercent %"
    Write-Log "Remediation finished."

    exit 0
}


Write-Log "LOW DISK SPACE detected!"
Write-Log "Free space is $($Before.FreePercent) %, below threshold $MinimumFreePercent %"


# ============================================================
# CLEANUP
# ============================================================


# 1. User-independent Windows Temp
Clear-TempFolder -Path "C:\Windows\Temp"


# 2. System Temp
Clear-TempFolder -Path "C:\Windows\SystemTemp"


# 3. Windows Update cache
Clear-WindowsUpdateCache


# 4. Delivery Optimization
Clear-DeliveryOptimization


# 5. Windows Error Reporting
Clear-WindowsErrorReporting


# 6. Recycle Bin
Clear-RecycleBinSafe

# 7. Windows.old
Remove-WindowsOld

# 8. DISM Component Store
Invoke-ComponentCleanup


# ============================================================
# CHECK RESULT
# ============================================================

$After = Get-DiskInformation

if (-not $After) {

    Write-Log "Could not determine disk space after cleanup." "ERROR"

    exit 1
}


$FreedGB = [math]::Round(
    ($After.FreeBytes - $Before.FreeBytes) / 1GB,
    2
)


Write-Log "============================================================"
Write-Log "Cleanup completed"
Write-Log "============================================================"

Write-Log "Before cleanup: $($Before.FreeGB) GB free ($($Before.FreePercent) %)"
Write-Log "After cleanup:  $($After.FreeGB) GB free ($($After.FreePercent) %)"
Write-Log "Space freed: $FreedGB GB"


# ------------------------------------------------------------
# Final status
# ------------------------------------------------------------

if ($After.FreePercent -ge $MinimumFreePercent) {

    Write-Log "STATUS: SUCCESS - Disk space is now above threshold."

    exit 0
}
else {

    Write-Log "STATUS: WARNING - Disk space is still below $MinimumFreePercent % after cleanup." "WARNING"

    exit 1
}
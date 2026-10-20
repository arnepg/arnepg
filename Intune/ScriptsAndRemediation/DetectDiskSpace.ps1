# ============================================================
# Intune Detection Script - Disk Space
# Checks free disk space on C:
# Exit 0 = OK
# Exit 1 = Less than 10% free space
#
# NOTES
#    FileName:    DetectDiskSpace.ps1
#    Author:      Arne P Groenmo
#    Created:     2026-10-05
#    Updated:     
#
# ============================================================

$MinimumFreePercent = 10
$DriveLetter = "C:"

try {
    # Get disk information
    $Disk = Get-CimInstance -ClassName Win32_LogicalDisk `
        -Filter "DeviceID='$DriveLetter'"

    if (-not $Disk) {
        Write-Output "ERROR: Could not find drive $DriveLetter"
        exit 1
    }

    # Calculate values
    $TotalBytes = [double]$Disk.Size
    $FreeBytes  = [double]$Disk.FreeSpace

    if ($TotalBytes -le 0) {
        Write-Output "ERROR: Invalid disk size detected"
        exit 1
    }

    $FreePercent = [math]::Round(
        ($FreeBytes / $TotalBytes) * 100,
        2
    )

    $FreeGB = [math]::Round(
        $FreeBytes / 1GB,
        2
    )

    $TotalGB = [math]::Round(
        $TotalBytes / 1GB,
        2
    )

    # Output disk information
    Write-Output "Drive: $DriveLetter"
    Write-Output "Total disk space: $TotalGB GB"
    Write-Output "Free disk space: $FreeGB GB"
    Write-Output "Free disk space: $FreePercent %"

    # Check threshold
    if ($FreePercent -lt $MinimumFreePercent) {
        Write-Output "STATUS: LOW DISK SPACE - Below $MinimumFreePercent%"
        exit 1
    }
    else {
        Write-Output "STATUS: OK - At least $MinimumFreePercent% free space available"
        exit 0
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
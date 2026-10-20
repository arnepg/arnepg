# ============================================================
# Intune Remediation - Detection
# Azure AD / Entra PRT Health Check
# ============================================================
#
# Run as:
#   Logged-on user = YES
#
# Exit 0 = Healthy / No remediation
# Exit 1 = Remediation required
#
# Log:
#   C:\Temp\Logs\AAD-JoinError.log
#
# NOTES
#    FileName:    DetectDeviceJoin.ps1
#    Author:      Arne P Groenmo
#    Created:     2026-10-02
#    Updated:     
#
# ============================================================

$LogPath = "C:\Temp\Logs\AAD-JoinError.log"

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
        $LogDirectory = Split-Path -Path $LogPath -Parent

        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force |
                Out-Null
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $ComputerName = $env:COMPUTERNAME

        Add-Content -Path $LogPath -Value `
            "$Timestamp [$Level] [$ComputerName] $Message" `
            -Encoding UTF8
    }
    catch {
        # Logging must never break detection
    }
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

Write-Log "============================================================"
Write-Log "Starting Azure AD / PRT detection."

# ------------------------------------------------------------
# Determine correct dsregcmd path
# ------------------------------------------------------------

$DsregCmd = "$env:SystemRoot\System32\dsregcmd.exe"

if (-not [Environment]::Is64BitProcess) {

    $SysnativeDsreg = "$env:SystemRoot\Sysnative\dsregcmd.exe"

    if (Test-Path $SysnativeDsreg) {
        $DsregCmd = $SysnativeDsreg
    }
}

Write-Log "PowerShell 64-bit: $([Environment]::Is64BitProcess)"
Write-Log "dsregcmd path: $DsregCmd"

# ------------------------------------------------------------
# Check dsregcmd
# ------------------------------------------------------------

if (-not (Test-Path $DsregCmd)) {

    Write-Log "dsregcmd.exe not found." "ERROR"

    # Do NOT trigger potentially destructive remediation
    exit 0
}

# ------------------------------------------------------------
# Run dsregcmd
# ------------------------------------------------------------

try {

    $Output = & $DsregCmd /status 2>&1

}
catch {

    Write-Log "Failed to execute dsregcmd: $($_.Exception.Message)" "ERROR"

    # Do NOT trigger remediation if status cannot be determined
    exit 0
}

if (-not $Output) {

    Write-Log "dsregcmd returned no output." "ERROR"

    exit 0
}

# ------------------------------------------------------------
# Function to extract dsregcmd values
# ------------------------------------------------------------

function Get-DsregValue {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Line = $Output |
        Where-Object {
            $_ -match "^\s*$Name\s*:"
        } |
        Select-Object -First 1

    if ($null -ne $Line) {
        return (($Line -split ":", 2)[1]).Trim()
    }

    return $null
}

# ------------------------------------------------------------
# Get values
# ------------------------------------------------------------

$AzureAdJoined = Get-DsregValue "AzureAdJoined"
$DomainJoined  = Get-DsregValue "DomainJoined"
$AzureAdPrt    = Get-DsregValue "AzureAdPrt"

# ------------------------------------------------------------
# Log state
# ------------------------------------------------------------

Write-Log "AzureAdJoined = [$AzureAdJoined]"
Write-Log "DomainJoined  = [$DomainJoined]"
Write-Log "AzureAdPrt    = [$AzureAdPrt]"

# ------------------------------------------------------------
# Healthy
# ------------------------------------------------------------

if (($AzureAdJoined -eq "YES") -and
    ($DomainJoined -eq "YES") -and
    ($AzureAdPrt -eq "YES")) {

    Write-Log "COMPLIANT: Azure AD PRT is available."
    Write-Log "Detection completed."
    Write-Log "============================================================"

    exit 0
}

# ------------------------------------------------------------
# Remediation required
# ------------------------------------------------------------

if (($AzureAdJoined -eq "YES") -and
    ($DomainJoined -eq "YES") -and
    ($AzureAdPrt -eq "NO")) {

    Write-Log "NON-COMPLIANT: AzureAdPrt = NO." "WARNING"
    Write-Log "Remediation required."
    Write-Log "============================================================"

    exit 1
}

# ------------------------------------------------------------
# Unknown state
# ------------------------------------------------------------

Write-Log "Unable to determine a safe remediation state." "WARNING"
Write-Log "No remediation will be triggered."
Write-Log "============================================================"

exit 0
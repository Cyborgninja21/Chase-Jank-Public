#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies registry settings defined in a JSON configuration file.

.DESCRIPTION
    Reads registry entries from a JSON file and sets each value in the Windows
    registry.  Creates registry keys that do not already exist.  Supports all
    common value types: DWord, QWord, String, ExpandString, MultiString, Binary.

.PARAMETER ConfigPath
    Path to the JSON file containing registry settings.
    Defaults to "registry-settings.json" in the same folder as this script.

.EXAMPLE
    .\Set-RegistrySettings.ps1
    Applies settings from the default registry-settings.json.

.EXAMPLE
    .\Set-RegistrySettings.ps1 -ConfigPath "C:\configs\my-settings.json"
    Applies settings from a custom JSON file.

.NOTES
    Author:  Chase Jank
    Version: 1.0
    Date:    2026-02-18
#>

param(
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

# Default to registry-settings.json next to this script
if (-not $ConfigPath) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $ConfigPath = Join-Path $ScriptRoot "registry-settings.json"
}

# --- Validate config file exists ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

# --- Read and parse JSON ---
try {
    $json = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to parse JSON - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $json.settings -or $json.settings.Count -eq 0) {
    Write-Host "No registry settings found in config file." -ForegroundColor Yellow
    exit 0
}

Write-Host "Applying $($json.settings.Count) registry setting(s) from: $ConfigPath" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount    = 0

foreach ($entry in $json.settings) {
    $desc = if ($entry.description) { " ($($entry.description))" } else { "" }
    Write-Host "  [$($entry.path)] $($entry.name)$desc" -ForegroundColor White

    try {
        # Create the registry key if it doesn't exist
        if (-not (Test-Path $entry.path)) {
            New-Item -Path $entry.path -Force | Out-Null
            Write-Host "    Created key: $($entry.path)" -ForegroundColor DarkGray
        }

        # Determine the value type (default to String if not specified)
        $regType = if ($entry.type) { $entry.type } else { "String" }

        # Handle Binary type: convert JSON array to byte array
        $regValue = $entry.value
        if ($regType -eq "Binary" -and $regValue -is [System.Array]) {
            $regValue = [byte[]]$regValue
        }
        # Handle MultiString type: convert JSON array to string array
        if ($regType -eq "MultiString" -and $regValue -is [System.Array]) {
            $regValue = [string[]]$regValue
        }

        Set-ItemProperty -Path $entry.path -Name $entry.name -Value $regValue -Type $regType
        Write-Host "    Set to: $($entry.value) ($regType)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# --- Summary ---
Write-Host ""
Write-Host "Done. $successCount succeeded, $failCount failed." -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })


# Netlify Desktop Monitor - EXE Builder
# Requires Windows PowerShell 5.1

$ErrorActionPreference = "Stop"

$Source = Join-Path $PSScriptRoot "NetlifyMonitor.ps1"
$Config = Join-Path $PSScriptRoot "config.json"
$Output = Join-Path $PSScriptRoot "dist"
$Exe = Join-Path $Output "NetlifyDesktopMonitor.exe"

Write-Host ""
Write-Host "NETLIFY DESKTOP MONITOR BUILDER" -ForegroundColor Cyan

if (-not (Test-Path $Source)) {
    throw "NetlifyMonitor.ps1 is missing."
}

if (-not (Test-Path $Config)) {
    throw "config.json is missing."
}

# Validate configuration
try {
    $settings = Get-Content $Config -Raw | ConvertFrom-Json

    foreach ($field in @("SiteUrl","NetlifyBadgeUrl","DashboardUrl")) {
        if ([string]::IsNullOrWhiteSpace([string]$settings.$field)) {
            throw "Missing configuration field: $field"
        }
    }
}
catch {
    throw "Invalid configuration: $($_.Exception.Message)"
}

# Install PS2EXE if needed
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force -Repository PSGallery
}

Import-Module ps2exe -ErrorAction Stop

# Create output directory
if (-not (Test-Path $Output)) {
    New-Item -ItemType Directory -Path $Output | Out-Null
}

# Build executable
Invoke-PS2EXE `
    -inputFile $Source `
    -outputFile $Exe `
    -noConsole `
    -STA `
    -title "Netlify Desktop Monitor"

# Copy configuration alongside executable
Copy-Item $Config (Join-Path $Output "config.json") -Force

if (-not (Test-Path $Exe)) {
    throw "Build failed: executable was not created."
}

Write-Host ""
Write-Host "BUILD SUCCESSFUL" -ForegroundColor Green
Write-Host "Executable saved to: $Exe"
Write-Host "Keep config.json beside the EXE."

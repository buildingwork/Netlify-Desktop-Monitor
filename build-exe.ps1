
# Netlify Desktop Monitor - EXE Builder

$ErrorActionPreference = "Stop"

$Source = Join-Path $PSScriptRoot "NetlifyMonitor.ps1"
$Output = Join-Path $PSScriptRoot "dist"
$Exe = Join-Path $Output "NetlifyDesktopMonitor.exe"

if (-not (Test-Path $Source)) {
    throw "NetlifyMonitor.ps1 not found."
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing PS2EXE for the current user..."

    Install-Module ps2exe `
        -Scope CurrentUser `
        -Force `
        -Repository PSGallery
}

Import-Module ps2exe -ErrorAction Stop

if (-not (Test-Path $Output)) {
    New-Item -ItemType Directory -Path $Output | Out-Null
}

Write-Host "Building Netlify Desktop Monitor..."

Invoke-PS2EXE `
    -inputFile $Source `
    -outputFile $Exe `
    -noConsole `
    -STA `
    -title "Netlify Desktop Monitor"

Copy-Item `
    (Join-Path $PSScriptRoot "config.json") `
    (Join-Path $Output "config.json") `
    -Force

Write-Host ""
Write-Host "BUILD COMPLETE!" -ForegroundColor Green
Write-Host "Executable: $Exe"
Write-Host "Remember to distribute config.json alongside the EXE."

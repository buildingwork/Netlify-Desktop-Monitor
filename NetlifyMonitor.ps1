
#requires -Version 5.1
# Netlify Desktop Monitor
# Copyright (c) 2026
# MIT License

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Find application folder (PowerShell or compiled EXE)
if ($PSScriptRoot) {
    $script:AppDirectory = $PSScriptRoot
}
elseif ($ScriptRoot) {
    $script:AppDirectory = $ScriptRoot
}
else {
    $script:AppDirectory = [AppDomain]::CurrentDomain.BaseDirectory
}

# Load configuration
$configPath = Join-Path $script:AppDirectory "config.json"

if (-not (Test-Path $configPath)) {
    [Windows.Forms.MessageBox]::Show(
        "config.json must be in the same folder as the application.",
        "Configuration error"
    ) | Out-Null
    exit
}

try {
    $script:Config = Get-Content $configPath -Raw | ConvertFrom-Json

    foreach ($field in @("SiteUrl","NetlifyBadgeUrl","DashboardUrl")) {
        if ([string]::IsNullOrWhiteSpace([string]$script:Config.$field)) {
            throw "Missing configuration field: $field"
        }
    }

    foreach ($url in @(
        $script:Config.SiteUrl,
        $script:Config.NetlifyBadgeUrl,
        $script:Config.DashboardUrl
    )) {
        if ($url -notmatch '^https://') {
            throw "All configured URLs must use HTTPS."
        }
    }

    $script:Timeout = [Math]::Max(5,[int]$script:Config.TimeoutSeconds)
    $script:Interval = [Math]::Max(30,[int]$script:Config.RefreshIntervalSeconds)
}
catch {
    [Windows.Forms.MessageBox]::Show(
        "Configuration error:`r`n$($_.Exception.Message)",
        "Netlify Desktop Monitor"
    ) | Out-Null
    exit
}

# Colours
$script:Green = [Drawing.Color]::FromArgb(65,190,125)
$script:Red = [Drawing.Color]::FromArgb(230,85,85)
$script:Yellow = [Drawing.Color]::FromArgb(235,185,65)
$script:White = [Drawing.Color]::White
$script:Grey = [Drawing.Color]::LightGray
$script:Background = [Drawing.Color]::FromArgb(28,30,38)

# Main window
$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = "Netlify Desktop Monitor"
$script:Form.Size = New-Object Drawing.Size(440,410)
$script:Form.StartPosition = "CenterScreen"
$script:Form.FormBorderStyle = "FixedDialog"
$script:Form.MaximizeBox = $false
$script:Form.BackColor = $script:Background

function Add-MonitorLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [int]$Size = 10,
        [Drawing.Color]$Color = $script:White
    )

    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point($X,$Y)
    $label.Size = New-Object Drawing.Size($Width,$Height)
    $label.Font = New-Object Drawing.Font("Segoe UI",$Size)
    $label.ForeColor = $Color
    $script:Form.Controls.Add($label)
    return $label
}

# Header
Add-MonitorLabel "NETLIFY DESKTOP MONITOR" 20 18 390 35 17 $script:White | Out-Null
Add-MonitorLabel "LIGHTWEIGHT WEBSITE MONITORING" 22 52 390 22 9 $script:Grey | Out-Null

$script:MainStatus = Add-MonitorLabel "READY TO CHECK" 20 91 390 42 22 $script:Yellow
$script:SiteStatus = Add-MonitorLabel "Website: Not checked" 22 151 390 25 10 $script:Grey
$script:DeployStatus = Add-MonitorLabel "Netlify: Not checked" 22 182 390 25 10 $script:Grey
$script:LastChecked = Add-MonitorLabel "Last checked: Never" 22 213 390 22 9 $script:Grey

# Refresh button
$script:RefreshButton = New-Object Windows.Forms.Button
$script:RefreshButton.Text = "REFRESH NOW"
$script:RefreshButton.Location = New-Object Drawing.Point(22,252)
$script:RefreshButton.Size = New-Object Drawing.Size(175,40)
$script:RefreshButton.BackColor = [Drawing.Color]::FromArgb(55,105,170)
$script:RefreshButton.ForeColor = $script:White
$script:RefreshButton.FlatStyle = "Flat"
$script:Form.Controls.Add($script:RefreshButton)

# Dashboard button
$script:DashboardButton = New-Object Windows.Forms.Button
$script:DashboardButton.Text = "NETLIFY DASHBOARD"
$script:DashboardButton.Location = New-Object Drawing.Point(207,252)
$script:DashboardButton.Size = New-Object Drawing.Size(190,40)
$script:DashboardButton.BackColor = [Drawing.Color]::FromArgb(55,60,75)
$script:DashboardButton.ForeColor = $script:White
$script:DashboardButton.FlatStyle = "Flat"
$script:Form.Controls.Add($script:DashboardButton)

# Automatic refresh OFF by default
$script:AutoRefresh = New-Object Windows.Forms.CheckBox
$script:AutoRefresh.Text = "Enable automatic refresh"
$script:AutoRefresh.Location = New-Object Drawing.Point(22,316)
$script:AutoRefresh.Size = New-Object Drawing.Size(250,25)
$script:AutoRefresh.ForeColor = $script:Grey
$script:AutoRefresh.Checked = $false
$script:Form.Controls.Add($script:AutoRefresh)

Add-MonitorLabel "Every $($script:Interval) seconds" 270 317 140 22 9 $script:Grey | Out-Null

# Timer exists but is not started
$script:Timer = New-Object Windows.Forms.Timer
$script:Timer.Interval = $script:Interval * 1000

# Background worker
$script:Worker = New-Object System.ComponentModel.BackgroundWorker

$script:Worker.add_DoWork({
    param($sender,$e)

    $settings = $e.Argument

    $result = [ordered]@{
        SiteCode = 0
        SiteReachable = $false
        SiteHealthy = $false
        DeployStatus = "UNKNOWN"
    }

    # Website check
    try {
        $response = Invoke-WebRequest `
            -Uri $settings.SiteUrl `
            -UseBasicParsing `
            -TimeoutSec $settings.Timeout `
            -MaximumRedirection 5 `
            -ErrorAction Stop

        $result.SiteCode = [int]$response.StatusCode
        $result.SiteReachable = $true
        $result.SiteHealthy = (
            $result.SiteCode -ge 200 -and
            $result.SiteCode -lt 400
        )
    }
    catch {
        $httpResponse = $_.Exception.Response

        if ($null -ne $httpResponse) {
            $result.SiteCode = [int]$httpResponse.StatusCode
            $result.SiteReachable = $true
            $result.SiteHealthy = (
                $result.SiteCode -ge 200 -and
                $result.SiteCode -lt 400
            )
        }
    }

    # Netlify deployment check
    try {
        $badge = Invoke-WebRequest `
            -Uri $settings.BadgeUrl `
            -UseBasicParsing `
            -TimeoutSec $settings.Timeout `
            -ErrorAction Stop

        $disposition = [string]$badge.Headers["Content-Disposition"]

        if ($disposition -match '(?i)badge-success') {
            $result.DeployStatus = "SUCCESS"
        }
        elseif ($disposition -match '(?i)badge-failed') {
            $result.DeployStatus = "FAILED"
        }
        elseif ($disposition -match '(?i)badge-building') {
            $result.DeployStatus = "BUILDING"
        }
        elseif ($disposition -match '(?i)badge-canceled') {
            $result.DeployStatus = "CANCELED"
        }
    }
    catch {
        $result.DeployStatus = "ERROR"
    }

    $e.Result = [PSCustomObject]$result
})

# Background worker completed
$script:Worker.add_RunWorkerCompleted({
    param($sender,$e)

    $script:RefreshButton.Enabled = $true
    $script:RefreshButton.Text = "REFRESH NOW"

    if ($e.Error) {
        $script:MainStatus.Text = "CHECK ERROR"
        $script:MainStatus.ForeColor = $script:Red
        return
    }

    $r = $e.Result

    if ($r.SiteHealthy) {
        $script:SiteStatus.Text = "Website: ONLINE (HTTP $($r.SiteCode))"
        $script:SiteStatus.ForeColor = $script:Green
    }
    elseif ($r.SiteReachable) {
        $script:SiteStatus.Text = "Website: HTTP $($r.SiteCode)"
        $script:SiteStatus.ForeColor = $script:Yellow
    }
    else {
        $script:SiteStatus.Text = "Website: UNREACHABLE"
        $script:SiteStatus.ForeColor = $script:Red
    }

    switch ($r.DeployStatus) {
        "SUCCESS" {
            $script:DeployStatus.Text = "Netlify: DEPLOYMENT SUCCESSFUL"
            $script:DeployStatus.ForeColor = $script:Green
        }
        "FAILED" {
            $script:DeployStatus.Text = "Netlify: DEPLOYMENT FAILED"
            $script:DeployStatus.ForeColor = $script:Red
        }
        "BUILDING" {
            $script:DeployStatus.Text = "Netlify: BUILDING"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
        "CANCELED" {
            $script:DeployStatus.Text = "Netlify: CANCELED"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
        default {
            $script:DeployStatus.Text = "Netlify: STATUS UNKNOWN"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
    }

    if (-not $r.SiteReachable -or -not $r.SiteHealthy) {
        $script:MainStatus.Text = "SITE UNAVAILABLE"
        $script:MainStatus.ForeColor = $script:Red
    }
    elseif ($r.DeployStatus -eq "SUCCESS") {
        $script:MainStatus.Text = "LIVE"
        $script:MainStatus.ForeColor = $script:Green
    }
    elseif ($r.DeployStatus -eq "FAILED") {
        $script:MainStatus.Text = "SITE ONLINE / DEPLOY FAILED"
        $script:MainStatus.ForeColor = $script:Yellow
    }
    else {
        $script:MainStatus.Text = "SITE ONLINE / CHECK DEPLOY"
        $script:MainStatus.ForeColor = $script:Yellow
    }

    $script:LastChecked.Text = "Last checked: " + (
        Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    )
})

# Start background check
function Start-StatusCheck {
    if ($script:Worker.IsBusy) {
        return
    }

    $script:RefreshButton.Enabled = $false
    $script:RefreshButton.Text = "CHECKING..."
    $script:MainStatus.Text = "CHECKING..."
    $script:MainStatus.ForeColor = $script:Yellow

    $script:Worker.RunWorkerAsync(@{
        SiteUrl = $script:Config.SiteUrl
        BadgeUrl = $script:Config.NetlifyBadgeUrl
        Timeout = $script:Timeout
    })
}

# Events
$script:RefreshButton.Add_Click({
    Start-StatusCheck
})

$script:DashboardButton.Add_Click({
    Start-Process $script:Config.DashboardUrl
})

$script:AutoRefresh.Add_CheckedChanged({
    if ($script:AutoRefresh.Checked) {
        $script:Timer.Start()
    }
    else {
        $script:Timer.Stop()
    }
})

$script:Timer.Add_Tick({
    Start-StatusCheck
})

$script:Form.Add_FormClosing({
    $script:Timer.Stop()
    $script:Timer.Dispose()
})

# Display without automatically checking
[void]$script:Form.ShowDialog()


#requires -Version 5.1
# Netlify Desktop Monitor
# Copyright (c) 2026
# MIT License

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Locate application files
if ($PSScriptRoot) {
    $script:AppDirectory = $PSScriptRoot
}
else {
    $script:AppDirectory = [AppDomain]::CurrentDomain.BaseDirectory
}

# Load configuration
$configPath = Join-Path $script:AppDirectory "config.json"

if (-not (Test-Path $configPath)) {
    [Windows.Forms.MessageBox]::Show(
        "config.json must be in the same folder as the application.",
        "Configuration error",
        "OK",
        "Error"
    ) | Out-Null
    exit
}

try {
    $script:Config = Get-Content $configPath -Raw | ConvertFrom-Json

    foreach ($field in @("SiteUrl", "NetlifyBadgeUrl", "DashboardUrl")) {
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

    $script:Timeout = [Math]::Max(5, [int]$script:Config.TimeoutSeconds)
    $script:Interval = [Math]::Max(30, [int]$script:Config.RefreshIntervalSeconds)
}
catch {
    [Windows.Forms.MessageBox]::Show(
        "Configuration error:`r`n$($_.Exception.Message)",
        "Netlify Desktop Monitor",
        "OK",
        "Error"
    ) | Out-Null
    exit
}

# Theme
$script:Green = [Drawing.Color]::FromArgb(65,190,125)
$script:Red = [Drawing.Color]::FromArgb(230,85,85)
$script:Yellow = [Drawing.Color]::FromArgb(235,185,65)
$script:White = [Drawing.Color]::White
$script:Grey = [Drawing.Color]::LightGray
$script:Background = [Drawing.Color]::FromArgb(28,30,38)

# Window
$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = "Netlify Desktop Monitor"
$script:Form.Size = New-Object Drawing.Size(440,410)
$script:Form.StartPosition = "CenterScreen"
$script:Form.FormBorderStyle = "FixedDialog"
$script:Form.MaximizeBox = $false
$script:Form.BackColor = $script:Background
$script:Form.Font = New-Object Drawing.Font("Segoe UI",10)

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

Add-MonitorLabel "NETLIFY DESKTOP MONITOR" 20 18 390 35 17 $script:White | Out-Null
Add-MonitorLabel "LIGHTWEIGHT WEBSITE MONITORING" 22 52 390 22 9 $script:Grey | Out-Null

$script:MainStatus = Add-MonitorLabel "READY TO CHECK" 20 91 390 42 22 $script:Yellow
$script:SiteStatus = Add-MonitorLabel "Website: Not checked" 22 151 390 25 10 $script:Grey
$script:DeployStatus = Add-MonitorLabel "Netlify: Not checked" 22 182 390 25 10 $script:Grey
$script:LastChecked = Add-MonitorLabel "Last checked: Never" 22 213 390 22 9 $script:Grey

# Buttons
$script:RefreshButton = New-Object Windows.Forms.Button
$script:RefreshButton.Text = "REFRESH NOW"
$script:RefreshButton.Location = New-Object Drawing.Point(22,252)
$script:RefreshButton.Size = New-Object Drawing.Size(175,40)
$script:RefreshButton.BackColor = [Drawing.Color]::FromArgb(55,105,170)
$script:RefreshButton.ForeColor = $script:White
$script:RefreshButton.FlatStyle = "Flat"
$script:Form.Controls.Add($script:RefreshButton)

$script:DashboardButton = New-Object Windows.Forms.Button
$script:DashboardButton.Text = "NETLIFY DASHBOARD"
$script:DashboardButton.Location = New-Object Drawing.Point(207,252)
$script:DashboardButton.Size = New-Object Drawing.Size(190,40)
$script:DashboardButton.BackColor = [Drawing.Color]::FromArgb(55,60,75)
$script:DashboardButton.ForeColor = $script:White
$script:DashboardButton.FlatStyle = "Flat"
$script:Form.Controls.Add($script:DashboardButton)

# Automatic refresh: deliberately OFF
$script:AutoRefresh = New-Object Windows.Forms.CheckBox
$script:AutoRefresh.Text = "Enable automatic refresh"
$script:AutoRefresh.Location = New-Object Drawing.Point(22,316)
$script:AutoRefresh.Size = New-Object Drawing.Size(250,25)
$script:AutoRefresh.ForeColor = $script:Grey
$script:AutoRefresh.Checked = $false
$script:Form.Controls.Add($script:AutoRefresh)

Add-MonitorLabel "Every $($script:Interval) seconds" 270 317 140 22 9 $script:Grey | Out-Null

# Timer is never started automatically
$script:Timer = New-Object Windows.Forms.Timer
$script:Timer.Interval = $script:Interval * 1000

# Background worker keeps network activity off the UI thread
$script:Worker = New-Object System.ComponentModel.BackgroundWorker

$script:Worker.add_DoWork({
    param($sender, $e)

    $settings = $e.Argument

    $result = [ordered]@{
        SiteCode = 0
        SiteReachable = $false
        SiteHealthy = $false
        SiteError = $null
        DeployStatus = "UNKNOWN"
        DeployError = $null
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
        else {
            $result.SiteError = $_.Exception.Message
        }
    }

    # Netlify badge check
    try {
        $badge = Invoke-WebRequest `
            -Uri $settings.BadgeUrl `
            -UseBasicParsing `
            -TimeoutSec $settings.Timeout `
            -ErrorAction Stop

        # Netlify identifies its deployment status in
        # the Content-Disposition filename.
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
        else {
            $result.DeployStatus = "UNKNOWN"
        }
    }
    catch {
        $result.DeployError = $_.Exception.Message
    }

    $e.Result = [PSCustomObject]$result
})

# Update interface after the background work completes
$script:Worker.add_RunWorkerCompleted({
    param($sender, $e)

    $script:RefreshButton.Enabled = $true
    $script:RefreshButton.Text = "REFRESH NOW"

    if ($e.Error) {
        $script:MainStatus.Text = "CHECK ERROR"
        $script:MainStatus.ForeColor = $script:Red
        $script:LastChecked.Text = $e.Error.Message
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
            $script:DeployStatus.Text = "Netlify: DEPLOYMENT CANCELED"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
        default {
            $script:DeployStatus.Text = "Netlify: STATUS UNKNOWN"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
    }

    # Report website health separately from deployment health
    if (-not $r.SiteReachable) {
        $script:MainStatus.Text = "SITE UNREACHABLE"
        $script:MainStatus.ForeColor = $script:Red
    }
    elseif (-not $r.SiteHealthy) {
        $script:MainStatus.Text = "SITE HTTP ERROR"
        $script:MainStatus.ForeColor = $script:Red
    }
    elseif ($r.DeployStatus -eq "FAILED") {
        $script:MainStatus.Text = "SITE ONLINE / DEPLOY FAILED"
        $script:MainStatus.ForeColor = $script:Yellow
    }
    elseif ($r.DeployStatus -eq "SUCCESS") {
        $script:MainStatus.Text = "LIVE"
        $script:MainStatus.ForeColor = $script:Green
    }
    elseif ($r.DeployStatus -eq "BUILDING") {
        $script:MainStatus.Text = "SITE ONLINE / BUILDING"
        $script:MainStatus.ForeColor = $script:Yellow
    }
    else {
        $script:MainStatus.Text = "SITE ONLINE / DEPLOY UNKNOWN"
        $script:MainStatus.ForeColor = $script:Yellow
    }

    $script:LastChecked.Text = "Last checked: " + (
        Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    )
})

# Start a check without blocking the window
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

$script:RefreshButton.Add_Click({
    Start-StatusCheck
})

$script:DashboardButton.Add_Click({
    try {
        Start-Process $script:Config.DashboardUrl
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            "Unable to open the Netlify dashboard.",
            "Error"
        ) | Out-Null
    }
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

# No automatic check at startup
[void]$script:Form.ShowDialog()

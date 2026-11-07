
#requires -Version 5.1
# Netlify Desktop Monitor
# Copyright (c) 2026
# MIT License

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Find application directory
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $script:AppDirectory = [AppDomain]::CurrentDomain.BaseDirectory
} else {
    $script:AppDirectory = $PSScriptRoot
}

# Load configuration
$configPath = Join-Path $script:AppDirectory "config.json"

if (-not (Test-Path $configPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "config.json is missing. Please restore it alongside the application.",
        "Configuration error",
        "OK",
        "Error"
    ) | Out-Null
    exit
}

try {
    $script:Config = Get-Content $configPath -Raw |
        ConvertFrom-Json
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Unable to read config.json.",
        "Configuration error",
        "OK",
        "Error"
    ) | Out-Null
    exit
}

$script:SiteUrl = $script:Config.SiteUrl
$script:BadgeUrl = $script:Config.NetlifyBadgeUrl
$script:DashboardUrl = $script:Config.DashboardUrl
$script:Timeout = [int]$script:Config.TimeoutSeconds
$script:Interval = [int]$script:Config.RefreshIntervalSeconds

# Colours
$script:Green = [Drawing.Color]::FromArgb(65, 190, 125)
$script:Red = [Drawing.Color]::FromArgb(230, 85, 85)
$script:Yellow = [Drawing.Color]::FromArgb(235, 185, 65)
$script:White = [Drawing.Color]::White
$script:Grey = [Drawing.Color]::LightGray
$script:Background = [Drawing.Color]::FromArgb(28, 30, 38)

# Main window
$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = "Netlify Desktop Monitor"
$script:Form.Size = New-Object Drawing.Size(430, 390)
$script:Form.StartPosition = "CenterScreen"
$script:Form.FormBorderStyle = "FixedDialog"
$script:Form.MaximizeBox = $false
$script:Form.BackColor = $script:Background
$script:Form.Font = New-Object Drawing.Font("Segoe UI", 10)

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
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($Width, $Height)
    $label.Font = New-Object Drawing.Font("Segoe UI", $Size)
    $label.ForeColor = $Color
    $script:Form.Controls.Add($label)

    return $label
}

# Header
Add-MonitorLabel "NETLIFY DESKTOP MONITOR" 20 18 380 35 17 $script:White | Out-Null
Add-MonitorLabel "LIGHTWEIGHT WEBSITE MONITORING" 22 52 380 22 9 $script:Grey | Out-Null

# Overall status
$script:MainStatus = Add-MonitorLabel "READY TO CHECK" 20 91 380 42 23 $script:Yellow

# Website information
$script:SiteStatus = Add-MonitorLabel "Website: Not checked" 22 151 380 25 10 $script:Grey
$script:DeployStatus = Add-MonitorLabel "Netlify: Not checked" 22 182 380 25 10 $script:Grey
$script:LastChecked = Add-MonitorLabel "Last checked: Never" 22 213 380 22 9 $script:Grey

# Refresh button
$script:RefreshButton = New-Object Windows.Forms.Button
$script:RefreshButton.Text = "REFRESH NOW"
$script:RefreshButton.Location = New-Object Drawing.Point(22, 252)
$script:RefreshButton.Size = New-Object Drawing.Size(175, 40)
$script:RefreshButton.BackColor = [Drawing.Color]::FromArgb(55, 105, 170)
$script:RefreshButton.ForeColor = $script:White
$script:RefreshButton.FlatStyle = "Flat"
$script:Form.Controls.Add($script:RefreshButton)

# Dashboard button
$script:DashboardButton = New-Object Windows.Forms.Button
$script:DashboardButton.Text = "NETLIFY DASHBOARD"
$script:DashboardButton.Location = New-Object Drawing.Point(207, 252)
$script:DashboardButton.Size = New-Object Drawing.Size(190, 40)
$script:DashboardButton.BackColor = [Drawing.Color]::FromArgb(55, 60, 75)
$script:DashboardButton.ForeColor = $script:White
$script:DashboardButton.FlatStyle = "Flat"
$script:Form.Controls.Add($script:DashboardButton)

# Automatic refresh: OFF by default
$script:AutoRefresh = New-Object Windows.Forms.CheckBox
$script:AutoRefresh.Text = "Enable automatic refresh"
$script:AutoRefresh.Location = New-Object Drawing.Point(22, 316)
$script:AutoRefresh.Size = New-Object Drawing.Size(250, 25)
$script:AutoRefresh.ForeColor = $script:Grey
$script:AutoRefresh.Checked = $false
$script:Form.Controls.Add($script:AutoRefresh)

$script:IntervalLabel = Add-MonitorLabel (
    "Every $($script:Interval) seconds"
) 270 317 130 22 9 $script:Grey

# Timer is created but never started automatically
$script:Timer = New-Object Windows.Forms.Timer
$script:Timer.Interval = $script:Interval * 1000

# Check website and Netlify independently
function Check-Status {

    $script:RefreshButton.Enabled = $false
    $script:MainStatus.Text = "CHECKING..."
    $script:MainStatus.ForeColor = $script:Yellow
    $script:Form.Refresh()

    $siteOK = $false
    $deployOK = $false

    # Website check
    try {
        $siteResponse = Invoke-WebRequest `
            -Uri $script:SiteUrl `
            -UseBasicParsing `
            -TimeoutSec $script:Timeout

        $siteCode = [int]$siteResponse.StatusCode

        if ($siteCode -ge 200 -and $siteCode -lt 400) {
            $siteOK = $true
            $script:SiteStatus.Text = "Website: ONLINE (HTTP $siteCode)"
            $script:SiteStatus.ForeColor = $script:Green
        } else {
            $script:SiteStatus.Text = "Website: HTTP $siteCode"
            $script:SiteStatus.ForeColor = $script:Yellow
        }
    }
    catch {
        $script:SiteStatus.Text = "Website: UNAVAILABLE"
        $script:SiteStatus.ForeColor = $script:Red
    }

    # Netlify deployment badge check
    try {
        $badgeResponse = Invoke-WebRequest `
            -Uri $script:BadgeUrl `
            -UseBasicParsing `
            -TimeoutSec $script:Timeout

        $badgeText = [System.Net.WebUtility]::HtmlDecode(
            [regex]::Replace(
                [string]$badgeResponse.Content,
                '<[^>]*>',
                ' '
            )
        )

        $badgeText = $badgeText -replace '\s+', ' '

        if ($badgeText -match '(?i)\bPublished\b') {
            $deployOK = $true
            $script:DeployStatus.Text = "Netlify: PUBLISHED"
            $script:DeployStatus.ForeColor = $script:Green
        }
        elseif ($badgeText -match '(?i)\bFailed\b') {
            $script:DeployStatus.Text = "Netlify: DEPLOYMENT FAILED"
            $script:DeployStatus.ForeColor = $script:Red
        }
        elseif ($badgeText -match '(?i)\bBuilding\b') {
            $script:DeployStatus.Text = "Netlify: BUILDING"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
        else {
            $script:DeployStatus.Text = "Netlify: STATUS UNKNOWN"
            $script:DeployStatus.ForeColor = $script:Yellow
        }
    }
    catch {
        $script:DeployStatus.Text = "Netlify: CONNECTION ERROR"
        $script:DeployStatus.ForeColor = $script:Red
    }

    # Overall status
    if ($siteOK -and $deployOK) {
        $script:MainStatus.Text = "LIVE"
        $script:MainStatus.ForeColor = $script:Green
    }
    elseif (-not $siteOK) {
        $script:MainStatus.Text = "SITE UNAVAILABLE"
        $script:MainStatus.ForeColor = $script:Red
    }
    else {
        $script:MainStatus.Text = "CHECK DEPLOYMENT"
        $script:MainStatus.ForeColor = $script:Yellow
    }

    $script:LastChecked.Text = "Last checked: " + (
        Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    )

    $script:RefreshButton.Enabled = $true
}

# Manual refresh
$script:RefreshButton.Add_Click({
    Check-Status
})

# Open Netlify dashboard
$script:DashboardButton.Add_Click({
    try {
        Start-Process $script:DashboardUrl
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            "Unable to open the Netlify dashboard.",
            "Error"
        ) | Out-Null
    }
})

# Enable or disable automatic refreshing
$script:AutoRefresh.Add_CheckedChanged({
    if ($script:AutoRefresh.Checked) {
        $script:Timer.Start()
    }
    else {
        $script:Timer.Stop()
    }
})

$script:Timer.Add_Tick({
    Check-Status
})

# Clean shutdown
$script:Form.Add_FormClosing({
    $script:Timer.Stop()
    $script:Timer.Dispose()
})

# Launch without performing an automatic check
[void]$script:Form.ShowDialog()

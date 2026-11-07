
# Netlify Desktop Monitor

A lightweight Windows desktop application for monitoring website availability and Netlify deployment status.

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)

## Features

- Website availability monitoring.
- Netlify deployment status monitoring.
- Simple Windows desktop interface.
- Manual refresh.
- Optional automatic refresh.
- Automatic refreshing disabled by default.
- Configurable website and Netlify badge URLs.
- Direct Netlify dashboard access.
- Responsive interface using background network checks.
- No background service.
- No telemetry or tracking.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 or later.
- Internet connection.

## Quick Start

1. Download or clone this repository.
2. Edit config.json with your website details.
3. Double-click launch.bat.
4. Press REFRESH NOW to check your website.

## Configuration

Edit config.json:

```json
{
  "SiteUrl": "https://example.com",
  "NetlifyBadgeUrl": "YOUR_NETLIFY_BADGE_URL",
  "DashboardUrl": "YOUR_NETLIFY_DASHBOARD_URL",
  "TimeoutSeconds": 15,
  "RefreshIntervalSeconds": 60
}
```

## Build the Windows executable

Open PowerShell in the project directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build-exe.ps1
```

The build script installs PS2EXE if necessary.

The executable is generated in:

```text
dist/NetlifyDesktopMonitor.exe
```

Keep config.json alongside the executable.

## Monitoring behaviour

The application performs two independent checks:

1. Website availability using an HTTP request.
2. Netlify deployment status using the deployment badge.

Network checks run in the background to keep the interface responsive.

A successful HTTP response does not guarantee that every website feature is working correctly.

A successful deployment does not guarantee that the website is accessible.

Automatic refreshing is OFF by default.

No network requests are made until the user presses REFRESH NOW or enables automatic refreshing.

## Performance

Designed to be lightweight:

- No background service.
- No automatic checks at startup.
- No database.
- No telemetry.
- No unnecessary background activity.
- Prevents overlapping monitoring requests.

## Troubleshooting

### Website unavailable

Check your internet connection and website address.

### Netlify status unknown

Check that your Netlify badge is accessible and that the response headers contain a recognised deployment status.

### SSL/TLS error

Ensure Windows supports TLS 1.2 and its certificate store is up to date.

### Application does not start

Try launching the PowerShell version from a PowerShell window to see error messages.

## Contributing

Issues and pull requests are welcome.

Please test changes on Windows PowerShell 5.1 before submitting.

## Licence

MIT License. See LICENSE.

## Disclaimer

This project is an independent community utility and is not affiliated with or endorsed by Netlify.

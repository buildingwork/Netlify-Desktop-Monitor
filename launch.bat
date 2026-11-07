
@echo off
title Netlify Desktop Monitor

set "APP_DIR=%~dp0"

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%APP_DIR%NetlifyMonitor.ps1"

if errorlevel 1 (
    echo.
    echo The monitor encountered an error.
    pause
)

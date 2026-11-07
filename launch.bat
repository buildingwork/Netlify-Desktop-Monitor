
@echo off
title Netlify Desktop Monitor

cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0NetlifyMonitor.ps1"

if errorlevel 1 (
    echo.
    echo Netlify Desktop Monitor encountered an error.
    pause
)

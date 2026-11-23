@echo off
chcp 65001 >nul
cd /d "%~dp0"

where pwsh >nul 2>&1
if not errorlevel 1 (
  start "" pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0overlay.ps1"
) else (
  start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0overlay.ps1"
)

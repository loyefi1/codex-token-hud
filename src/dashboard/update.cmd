@echo off
chcp 65001 >nul
cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
  if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" (
    set "NODE=%LOCALAPPDATA%\Programs\nodejs\node.exe"
  ) else (
    echo Node.js not found. Install Node.js 18+ to rebuild the dashboard:
    echo   https://nodejs.org/
    pause
    exit /b 1
  )
) else (
  set "NODE=node"
)

"%NODE%" build.mjs
if errorlevel 1 (
  echo.
  echo Build failed. See the error above.
  pause
  exit /b 1
)

start "" "%~dp0index.html"

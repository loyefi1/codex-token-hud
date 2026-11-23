@echo off
cd /d "%~dp0"
if exist "index.html" (
  start "" "index.html"
) else (
  call "update.cmd"
)

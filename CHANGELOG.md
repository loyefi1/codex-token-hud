# Changelog

## 1.0.1

- Launch the HUD through a detached VBScript launcher (`wscript.exe launch.vbs`) so closing any PowerShell/console window no longer terminates the widget.
- Auto start now uses the same detached launcher.
- Added `src/hud/launch.vbs`; installer and release package include it.

## 1.0.0

- Floating always-on-top HUD for the ChatGPT / Codex desktop app.
- Follows the active conversation via Windows OCR of the chat header title.
- Auto width based on measured text; long model names no longer overflow.
- Transparent / translucent layered rendering, foreground-only visibility, drag and position lock, follow-window mode.
- Starts with Windows and exits together with the ChatGPT / Codex app.
- Offline HTML token dashboard with per-session, per-turn and per-request breakdown.
- Installer, uninstaller and release packaging scripts.

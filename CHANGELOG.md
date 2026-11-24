# Changelog

## 1.0.3

- Prefer a `thread/resume` entry from the last two minutes as the active thread; OCR of the chat header is used when no fresh resume exists.
- Fixes wrong model/stats right after switching conversations, especially when the header shows a workspace path.

## 1.0.2

- Read the active thread id from the Codex app-server log database (`logs_2.sqlite`, `thread/resume` events) through the system `winsqlite3.dll`.
- Thread resolution order is now: OCR title match → recent `thread/resume` log entry → last known thread → UI state file.
- Fixes the HUD keeping the previous model when the chat header shows a workspace path instead of a thread title.

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

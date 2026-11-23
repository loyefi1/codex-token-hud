# Codex Token HUD uninstaller
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'CodexTokenHUD'),
    [switch]$KeepFiles
)

$ErrorActionPreference = 'SilentlyContinue'

Write-Host ''
Write-Host 'Codex Token HUD uninstaller' -ForegroundColor Cyan

$pidFile = Join-Path $InstallDir 'overlay.pid'
if (Test-Path -LiteralPath $pidFile) {
    $hudPid = Get-Content -LiteralPath $pidFile
    if ($hudPid) { Stop-Process -Id $hudPid -Force }
    Remove-Item -LiteralPath $pidFile -Force
    Write-Host 'HUD stopped.'
}

Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'CodexHud'
Write-Host 'Auto start removed.'

$links = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex Token HUD.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Token HUD.lnk')
)
foreach ($lnk in $links) {
    if (Test-Path -LiteralPath $lnk) {
        Remove-Item -LiteralPath $lnk -Force
        Write-Host "Removed shortcut: $lnk"
    }
}

if ($KeepFiles) {
    Write-Host "Files kept at: $InstallDir"
} elseif (Test-Path -LiteralPath $InstallDir) {
    $resolved = (Resolve-Path -LiteralPath $InstallDir).Path
    if ($resolved -like '*CodexTokenHUD*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
        Write-Host "Removed: $resolved"
    } else {
        Write-Warning "Refusing to delete $resolved (folder name does not look like CodexTokenHUD)."
    }
}

Write-Host 'Done.' -ForegroundColor Cyan
Write-Host ''

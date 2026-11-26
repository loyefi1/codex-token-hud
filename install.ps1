# Codex Token HUD installer
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'CodexTokenHUD'),
    [switch]$NoStartup,
    [switch]$NoLaunch,
    [switch]$NoShortcut,
    [switch]$DesktopShortcut
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = '1.4.0'

function Resolve-Source([string]$relative, [string]$probe) {
    $path = Join-Path $root $relative
    if (Test-Path -LiteralPath (Join-Path $path $probe)) { return $path }
    if (Test-Path -LiteralPath (Join-Path $root $probe)) { return $root }
    throw "Cannot find source files (missing $probe). Run install.ps1 from the repository or release folder."
}

$srcHud = Resolve-Source 'src\hud' 'overlay.ps1'
$srcDash = Resolve-Source 'src\dashboard' 'build.mjs'

Write-Host ''
Write-Host "Codex Token HUD $version" -ForegroundColor Cyan
Write-Host "Install dir: $InstallDir"
Write-Host ''

# stop an existing copy first
$oldPidFile = Join-Path $InstallDir 'overlay.pid'
if (Test-Path -LiteralPath $oldPidFile) {
    $oldPid = Get-Content -LiteralPath $oldPidFile -ErrorAction SilentlyContinue
    if ($oldPid) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $oldPidFile -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Copy-Item -LiteralPath (Join-Path $srcHud 'overlay.ps1') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcHud 'start.cmd') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcHud 'launch.vbs') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcHud 'stop.cmd') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcDash 'build.mjs') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcDash 'template.html') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcDash 'update.cmd') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $srcDash 'open.cmd') -Destination $InstallDir -Force
if (Test-Path -LiteralPath (Join-Path $srcDash 'index.html')) {
    Copy-Item -LiteralPath (Join-Path $srcDash 'index.html') -Destination $InstallDir -Force
}
foreach ($name in 'README.md', 'LICENSE') {
    if (Test-Path -LiteralPath (Join-Path $root $name)) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $InstallDir -Force
    }
}
Set-Content -LiteralPath (Join-Path $InstallDir 'version.txt') -Value $version -Encoding ASCII

# build the HTML dashboard if Node.js is available
$nodeExe = $null
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeExe = $nodeCmd.Source
} elseif (Test-Path "$env:LOCALAPPDATA\Programs\nodejs\node.exe") {
    $nodeExe = "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
}
if ($nodeExe) {
    $pushed = $false
    try {
        Push-Location $InstallDir
        $pushed = $true
        & $nodeExe build.mjs
    } catch {
        Write-Warning "Dashboard build failed: $($_.Exception.Message)"
    } finally {
        if ($pushed) { Pop-Location }
    }
} else {
    Write-Warning 'Node.js not found. The HUD works, but the HTML dashboard needs Node.js 18+ (https://nodejs.org/).'
}

# Start Menu shortcut
if (-not $NoShortcut) {
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
    $lnkPath = Join-Path $startMenu 'Codex Token HUD.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($lnkPath)
    $shortcut.TargetPath = Join-Path $InstallDir 'start.cmd'
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,13"
    $shortcut.Description = 'Codex Token HUD - floating token usage overlay'
    $shortcut.Save()
}

if ($DesktopShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $desktopLnk = Join-Path $desktop 'Codex Token HUD.lnk'
    $d = $ws.CreateShortcut($desktopLnk)
    $d.TargetPath = Join-Path $InstallDir 'start.cmd'
    $d.WorkingDirectory = $InstallDir
    $d.IconLocation = "$env:SystemRoot\System32\shell32.dll,13"
    $d.Save()
}

# auto start with Windows (launches together with the ChatGPT / Codex app)
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (-not $NoStartup) {
    $cmd = 'wscript.exe "' + (Join-Path $InstallDir 'launch.vbs') + '"'
    Set-ItemProperty -Path $runKey -Name 'CodexHud' -Value $cmd
    Write-Host 'Auto start: enabled' -ForegroundColor Green
} else {
    Remove-ItemProperty -Path $runKey -Name 'CodexHud' -ErrorAction SilentlyContinue
    Write-Host 'Auto start: disabled'
}

if (-not (Test-Path "$env:USERPROFILE\.codex")) {
    Write-Warning 'Codex data directory (~\.codex) was not found. Start the ChatGPT/Codex desktop app once, then run the HUD.'
} else {
    Write-Host 'Codex data directory: found' -ForegroundColor Green
}

if (-not $NoLaunch) {
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" `
        -ArgumentList @('//nologo', ('"' + (Join-Path $InstallDir 'launch.vbs') + '"')) `
        -WindowStyle Hidden
    Write-Host 'HUD started (it appears when the ChatGPT/Codex window is in the foreground).' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
Write-Host "  Start Menu : Codex Token HUD"
Write-Host "  Dashboard  : $InstallDir\update.cmd"
Write-Host "  Uninstall  : $root\uninstall.ps1"
Write-Host ''
Write-Host 'Tips:'
Write-Host '  - Right-click the bar and use "固定位置" to lock/unlock its position.'
Write-Host '  - "打开统计看板" opens the HTML token dashboard.'
Write-Host ''

# Build the release ZIP (Windows PowerShell 5.1+ / PowerShell 7)
[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$distRoot = Join-Path $root 'dist'
$stage = Join-Path $distRoot "CodexTokenHUD-$Version"
$zip = Join-Path $distRoot "CodexTokenHUD-$Version.zip"

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Copy-Item -LiteralPath (Join-Path $root 'install.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'install.cmd') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'uninstall.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'README.zh-CN.md') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $stage

Copy-Item -LiteralPath (Join-Path $root 'src\hud\overlay.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'src\hud\start.cmd') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'src\hud\launch.vbs') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'src\hud\stop.cmd') -Destination $stage

Copy-Item -LiteralPath (Join-Path $root 'src\dashboard\build.mjs') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'src\dashboard\template.html') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'src\dashboard\update.cmd') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'src\dashboard\open.cmd') -Destination $stage


New-Item -ItemType Directory -Force -Path (Join-Path $stage 'docs\screenshots') | Out-Null
if (Test-Path -LiteralPath (Join-Path $root 'docs\screenshots\hud.png')) {
    Copy-Item -LiteralPath (Join-Path $root 'docs\screenshots\hud.png') -Destination (Join-Path $stage 'docs\screenshots')
}
if (Test-Path -LiteralPath (Join-Path $root 'docs\screenshots\dashboard.png')) {
    Copy-Item -LiteralPath (Join-Path $root 'docs\screenshots\dashboard.png') -Destination (Join-Path $stage 'docs\screenshots')
}

Set-Content -LiteralPath (Join-Path $stage 'version.txt') -Value $Version -Encoding ASCII

if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal

$size = [Math]::Round((Get-Item -LiteralPath $zip).Length / 1KB, 1)
Write-Host "Release created: $zip ($size KB)" -ForegroundColor Green

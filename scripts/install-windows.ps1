# Installs Y-Node Desktop into Program Files for every user.
#
#   powershell -ExecutionPolicy Bypass -File install-windows.ps1
#
# The script asks for administrator rights itself, copies the files next to it
# into %ProgramFiles%\Y-Node, creates Start Menu and desktop shortcuts and adds
# an uninstall entry to "Apps & features". No code-signing certificate is
# required: Windows SmartScreen may warn about an unknown publisher.

param(
  [string]$InstallDir = (Join-Path $env:ProgramFiles 'Y-Node'),
  [switch]$NoDesktopShortcut,
  [switch]$Launch
)

$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $source 'y_node_desktop.exe'
if (-not (Test-Path $exe)) {
  throw "y_node_desktop.exe was not found next to the installer: $source"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  # Elevate once and let the elevated copy do the work. Every argument is
  # quoted so a path with spaces survives the second launch.
  $arguments = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$PSCommandPath`"",
    '-InstallDir', "`"$InstallDir`""
  )
  if ($NoDesktopShortcut) { $arguments += '-NoDesktopShortcut' }
  if ($Launch) { $arguments += '-Launch' }
  Write-Host 'Administrator rights are required to install into Program Files.'
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
  exit
}

Write-Host "==> installing to $InstallDir"
# An update runs over the previous build, which may be running. The core is
# asked to restore the system proxy and stop the tunnel before the processes
# are terminated: a hard kill leaves the proxy pointing at a dead port, and a
# running executable keeps the files locked.
try {
  Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:7799/v1/quit' `
    -TimeoutSec 15 | Out-Null
} catch {
  # Not running, or an older build without the endpoint.
}
for ($i = 0; $i -lt 60; $i++) {
  if (-not (Get-Process -Name 'y-node-core' -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 250
}
Get-Process -Name 'y_node_desktop', 'y-node-core' -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Get-ChildItem -Path $source -File | Where-Object {
  $_.Name -notin @('install-windows.ps1', 'uninstall-windows.ps1')
} | Copy-Item -Destination $InstallDir -Force
Get-ChildItem -Path $source -Directory | ForEach-Object {
  Copy-Item $_.FullName -Destination $InstallDir -Recurse -Force
}

# The uninstaller is part of the installation, so the user can remove the app
# without keeping the original archive.
Copy-Item (Join-Path $source 'uninstall-windows.ps1') $InstallDir -Force

$shell = New-Object -ComObject WScript.Shell
$startMenu = [Environment]::GetFolderPath('CommonPrograms')
New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
$startShortcut = Join-Path $startMenu 'Y-Node.lnk'
$shortcut = $shell.CreateShortcut($startShortcut)
$shortcut.TargetPath = Join-Path $InstallDir 'y_node_desktop.exe'
$shortcut.WorkingDirectory = $InstallDir
$shortcut.Description = 'Y-Node for Windows'
$shortcut.IconLocation = Join-Path $InstallDir 'y_node_desktop.exe'
$shortcut.Save()

if (-not $NoDesktopShortcut) {
  $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
  $desktopShortcut = Join-Path $desktop 'Y-Node.lnk'
  $shortcut = $shell.CreateShortcut($desktopShortcut)
  $shortcut.TargetPath = Join-Path $InstallDir 'y_node_desktop.exe'
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.Description = 'Y-Node for Windows'
  $shortcut.IconLocation = Join-Path $InstallDir 'y_node_desktop.exe'
  $shortcut.Save()
}

$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Y-NodeDesktop'
$version = (Get-Item $exe).VersionInfo.ProductVersion
if ([string]::IsNullOrWhiteSpace($version)) { $version = '1.0.0' }
New-Item -Path $uninstallKey -Force | Out-Null
Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'Y-Node'
Set-ItemProperty -Path $uninstallKey -Name 'DisplayVersion' -Value $version
Set-ItemProperty -Path $uninstallKey -Name 'Publisher' -Value 'Y-Node'
Set-ItemProperty -Path $uninstallKey -Name 'InstallLocation' -Value $InstallDir
Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value (Join-Path $InstallDir 'y_node_desktop.exe')
Set-ItemProperty -Path $uninstallKey -Name 'UninstallString' -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir 'uninstall-windows.ps1')`""

Write-Host 'Y-Node is installed.'
if ($Launch) {
  # The elevated process must not start the window: the app writes the proxy
  # settings of the current user, and an elevated copy would write the
  # administrator profile instead.
  Write-Host 'Start Y-Node from the Start menu or the desktop shortcut.'
}

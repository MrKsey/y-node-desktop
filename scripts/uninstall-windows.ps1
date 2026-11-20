# Removes the installation created by install-windows.ps1 from Program Files.
# The script asks for administrator rights itself.
#
# Before anything is removed the user is asked whether the saved data should go
# as well. The data directory holds the configuration, the identity, the peer
# lists and the exit profiles: keeping it lets the next installation continue
# with the same address and the same peers, deleting it makes the next
# installation start from a clean slate.
#
#   powershell -ExecutionPolicy Bypass -File uninstall-windows.ps1
#   powershell -ExecutionPolicy Bypass -File uninstall-windows.ps1 -PurgeData
#   powershell -ExecutionPolicy Bypass -File uninstall-windows.ps1 -KeepData
#
# -PurgeData and -KeepData skip the question, which scripted removals use.

param(
  [string]$InstallDir = (Join-Path $env:ProgramFiles 'Y-Node'),
  [switch]$PurgeData,
  [switch]$KeepData
)

$ErrorActionPreference = 'Stop'

$dataDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Y-Node'
$internetSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

# The proxy address the app used, read before the data directory may be
# deleted. An empty string means the configuration is already gone.
function Get-AppProxyAddress {
  $path = Join-Path $dataDir 'config.json'
  if (-not (Test-Path $path)) { return '' }
  try {
    $config = Get-Content $path -Raw | ConvertFrom-Json
    $bind = if ($config.bind) { [string]$config.bind } else { '127.0.0.1' }
    $port = if ($config.httpPort) { [int]$config.httpPort } else { 7890 }
    return "${bind}:$port"
  } catch {
    return ''
  }
}

# The window restores the proxy on a graceful shutdown. A forced stop skips
# that, so the uninstaller restores the saved state itself: a browser must not
# keep pointing at a port that no longer exists. Only a proxy that belongs to
# this app is touched.
function Restore-SystemProxy([string]$Address) {  if (-not (Test-Path $internetSettings)) { return }
  $server = (Get-ItemProperty -Path $internetSettings -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
  if ($Address) {
    if ($server -ne $Address) { return }
  } elseif ($server -and $server -notmatch '^(127\.|localhost)') {
    return
  }
  $backupPath = Join-Path $dataDir 'system-proxy-backup.json'
  if (Test-Path $backupPath) {
    try {
      $backup = Get-Content $backupPath -Raw | ConvertFrom-Json
      if ($backup.hasServer) {
        Set-ItemProperty -Path $internetSettings -Name ProxyServer -Value ([string]$backup.server)
      } else {
        Remove-ItemProperty -Path $internetSettings -Name ProxyServer -ErrorAction SilentlyContinue
      }
      if ($backup.hasOverride) {
        Set-ItemProperty -Path $internetSettings -Name ProxyOverride -Value ([string]$backup.override)
      } else {
        Remove-ItemProperty -Path $internetSettings -Name ProxyOverride -ErrorAction SilentlyContinue
      }
      Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Value ([int]$backup.enable) -Type DWord
      Write-Host 'The previous system proxy settings were restored.'
      return
    } catch {
      Write-Host "The saved proxy settings could not be read: $($_.Exception.Message)"
    }
  }
  Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Value 0 -Type DWord
  Write-Host 'The system proxy was switched off.'
}

# A running core keeps the system proxy on and the TUN adapter busy, and a
# running executable keeps its files locked: the installation directory cannot
# be removed while either process lives. The core restores the proxy and drops
# the tunnel on a graceful stop, so it is asked first; only a core that does not
# answer is killed.
function Stop-YNodeProcesses {
  try {
    Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:7799/v1/quit' `
      -TimeoutSec 15 | Out-Null
  } catch {
    # The core is not running, or it is an older build without the endpoint:
    # the forced stop below covers both.
  }
  for ($i = 0; $i -lt 60; $i++) {
    if (-not (Get-Process -Name 'y-node-core' -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
  }
  # The window is a separate process: the core cannot close it.
  Get-Process -Name 'y_node_desktop' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Get-Process -Name 'y-node-core' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
}

# Yes removes the saved data, No keeps it; the safe answer is the default.
function Ask-RemoveData {  $message = "Delete all saved Y-Node data?`n`n" +
    "This removes the configuration, the private key, the peer lists and the saved exit profiles from:`n" +
    $dataDir + "`n`n" +
    "Choose No to keep them: the next installation then starts with the same identity and peers."
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [System.Windows.Forms.MessageBox]::Show(
      $message,
      'Uninstall Y-Node',
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Question,
      [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    return $answer -eq [System.Windows.Forms.DialogResult]::Yes
  } catch {
    $answer = Read-Host 'Delete all saved Y-Node data? [y/N]'
    return $answer -match '^\s*(?i)y'
  }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# The question is asked once, before the elevation: the elevated copy receives
# the answer as a switch and never asks again. A directory that does not exist
# means the app never stored anything, so there is nothing to ask about.
if (-not $PurgeData -and -not $KeepData) {
  if (-not (Test-Path $dataDir)) {
    $KeepData = $true
  } elseif (Ask-RemoveData) {
    $PurgeData = $true
  } else {
    $KeepData = $true
  }
}

if (-not $isAdmin) {
  $arguments = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$PSCommandPath`"",
    '-InstallDir', "`"$InstallDir`""
  )
  if ($PurgeData) { $arguments += '-PurgeData' } else { $arguments += '-KeepData' }
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
  exit
}

$proxyAddress = Get-AppProxyAddress

Stop-YNodeProcesses

Restore-SystemProxy $proxyAddress

$startMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Y-Node.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Y-Node.lnk'
foreach ($link in @($startMenu, $desktop)) {
  if (Test-Path $link) { Remove-Item $link -Force }
}
# The "Start with Windows" switch of the app writes this entry. Leaving it
# behind would make Windows try to launch a removed executable at every logon.
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
  -Name 'Y-Node' -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Y-NodeDesktop' -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) {
  Remove-Item $InstallDir -Recurse -Force
}

if ($PurgeData) {
  if (Test-Path $dataDir) {
    Remove-Item $dataDir -Recurse -Force
  }
  Write-Host "Saved data was removed: $dataDir"
} else {
  Write-Host "Saved data was kept: $dataDir"
}
Write-Host 'Y-Node was removed.'

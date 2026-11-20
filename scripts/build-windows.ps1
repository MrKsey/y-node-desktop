# Builds the Windows release bundle, the portable ZIP and the per-user
# installer.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#
# The result is written to dist\windows, dist\y-node-desktop-<version>-windows-x64.zip
# and, when Inno Setup is installed, dist\y-node-desktop-<version>-x64-setup.exe.

param(
  [string]$Version = '1.0.0',
  [string]$Configuration = 'Release',
  [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
# A tag is written as v1.5.5; the binaries and the archive use 1.5.5.
$Version = $Version -replace '^[vV]', ''
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
$core = Join-Path $root 'core'
$dist = Join-Path $root 'dist\windows'

function Find-Flutter {
  if ($env:FLUTTER_ROOT) { return Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat' }
  $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  throw 'Flutter is not on PATH. Set FLUTTER_ROOT or add flutter.bat to PATH.'
}

Write-Host '==> building the core'
Push-Location $core
try {
  go build -trimpath -ldflags "-s -w -X main.version=$Version" `
    -o "bin\y-node-core.exe" ./cmd/y-node-core
  if ($LASTEXITCODE -ne 0) { throw 'go build failed' }
} finally {
  Pop-Location
}

Write-Host '==> building the window'
Push-Location $app
try {
  & (Find-Flutter) build windows "--$($Configuration.ToLower())"
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
} finally {
  Pop-Location
}

$bundle = Join-Path $app "build\windows\x64\runner\$Configuration"
Copy-Item (Join-Path $core 'bin\y-node-core.exe') (Join-Path $bundle 'y-node-core.exe') -Force

Write-Host "==> copying to $dist"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Copy-Item (Join-Path $bundle '*') $dist -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'install-windows.ps1') $dist -Force
Copy-Item (Join-Path $PSScriptRoot 'uninstall-windows.ps1') $dist -Force

Write-Host '==> packing the portable ZIP'
$zip = Join-Path $root "dist\y-node-desktop-$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $zip -Force

if (-not $SkipInstaller) {
  $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
  if (-not $iscc) {
    foreach ($candidate in @(
      'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
      'C:\Program Files\Inno Setup 6\ISCC.exe',
      (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )) {
      if (Test-Path $candidate) { $iscc = $candidate; break }
    }
  }
  if ($iscc) {
    Write-Host '==> building the Inno Setup installer'
    & $iscc "/DMyVersion=$Version" (Join-Path $PSScriptRoot 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }
  } else {
    Write-Host 'Inno Setup is not installed; the portable ZIP is ready.'
    Write-Host 'Install it with: winget install --id JRSoftware.InnoSetup'
  }
}

Write-Host "Done: $zip"

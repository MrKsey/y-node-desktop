# Builds the Windows release bundle and the MSIX package.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#
# The result is written to dist\windows and dist\y-node-desktop-<version>-x64.msix.

param(
  [string]$Version = '1.0.0',
  [string]$Configuration = 'Release',
  [switch]$SkipMsix
)

$ErrorActionPreference = 'Stop'
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

if ($SkipMsix) {
  Write-Host "Done: $dist"
  exit 0
}

Write-Host '==> packing the MSIX'
$msix = Join-Path $root "dist\y-node-desktop-$Version-x64.msix"
$layout = Join-Path $root 'dist\msix'
if (Test-Path $layout) { Remove-Item $layout -Recurse -Force }
New-Item -ItemType Directory -Path $layout -Force | Out-Null

Copy-Item (Join-Path $PSScriptRoot 'msix\AppxManifest.xml') $layout -Force
Copy-Item (Join-Path $PSScriptRoot 'msix\Assets') (Join-Path $layout 'Assets') -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $layout 'VFS') -Force | Out-Null
Copy-Item (Join-Path $dist '*') (Join-Path $layout 'VFS') -Recurse -Force

$manifest = Join-Path $layout 'AppxManifest.xml'
(Get-Content $manifest -Raw).Replace('__VERSION__', "$Version.0") |
  Set-Content $manifest -Encoding UTF8 -NoNewline

$kit = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory |
  Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
if (-not $kit) { throw 'The Windows SDK was not found: install it from the Visual Studio installer' }
$makeappx = Join-Path $kit.FullName 'x64\makeappx.exe'
$signtool = Join-Path $kit.FullName 'x64\signtool.exe'
if (-not (Test-Path $makeappx)) { throw "makeappx.exe not found in $($kit.FullName)" }

& $makeappx pack /o /d $layout /p $msix
if ($LASTEXITCODE -ne 0) { throw 'makeappx failed' }

$cert = Join-Path $root 'dist\y-node-desktop-test.pfx'
$password = 'y-node-desktop'
if (-not (Test-Path $cert)) {
  Write-Host '==> creating a self-signed certificate for the package'
  $secure = ConvertTo-SecureString -String $password -Force -AsPlainText
  $created = New-SelfSignedCertificate -Type Custom -Subject 'CN=NLP-Core-Team' `
    -KeyUsage DigitalSignature -FriendlyName 'Y-Node Desktop (test)' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
  $created | Export-PfxCertificate -FilePath $cert -Password $secure | Out-Null
  Export-Certificate -Cert $created -FilePath (Join-Path $root 'dist\y-node-desktop-test.cer') | Out-Null
}

& $signtool sign /fd SHA256 /f $cert /p $password $msix
if ($LASTEXITCODE -ne 0) { throw 'signtool failed' }

Write-Host "Done: $msix"

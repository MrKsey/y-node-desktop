# Rebuilds the Windows icon files from the 256 px master.
#
#   powershell -ExecutionPolicy Bypass -File scripts\make-icons.ps1
#
# Windows draws a shortcut icon with the frame that matches the requested size.
# The previous file stored every frame as PNG, which Explorer sometimes scales
# instead of using as-is, and the rounded corners were lost on the taskbar.
# Frames up to 64 px are therefore stored as uncompressed DIBs, which every
# shell version reads natively; 128 and 256 stay PNG, the format the ICO
# container expects for those sizes.
param(
  [string]$Source = (Join-Path $PSScriptRoot '..\app\assets\app_icon.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$targets = @(
  (Join-Path $root 'app\windows\runner\resources\app_icon.ico'),
  (Join-Path $root 'app\assets\tray_icon.ico')
)

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$pngSizes = @(128, 256)

function New-Scaled([System.Drawing.Image]$image, [int]$size) {
  $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.DrawImage($image, 0, 0, $size, $size)
  } finally {
    $graphics.Dispose()
  }
  return $bitmap
}

function Get-DibBytes([System.Drawing.Bitmap]$bitmap) {
  $width = $bitmap.Width
  $height = $bitmap.Height
  $stream = New-Object System.IO.MemoryStream
  $writer = New-Object System.IO.BinaryWriter($stream)
  try {
    $writer.Write([uint32]40)
    $writer.Write([int32]$width)
    $writer.Write([int32]($height * 2))
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]0)
    $writer.Write([uint32]($width * $height * 4))
    $writer.Write([int32]0)
    $writer.Write([int32]0)
    $writer.Write([uint32]0)
    $writer.Write([uint32]0)
    for ($y = $height - 1; $y -ge 0; $y--) {
      for ($x = 0; $x -lt $width; $x++) {
        $color = $bitmap.GetPixel($x, $y)
        $writer.Write([byte]$color.B)
        $writer.Write([byte]$color.G)
        $writer.Write([byte]$color.R)
        $writer.Write([byte]$color.A)
      }
    }
    $rowBytes = [int][math]::Ceiling($width / 8.0)
    $padding = (4 - ($rowBytes % 4)) % 4
    $maskRow = New-Object byte[] ($rowBytes + $padding)
    for ($y = 0; $y -lt $height; $y++) {
      $writer.Write($maskRow, 0, $maskRow.Length)
    }
    $writer.Flush()
    return $stream.ToArray()
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Get-PngBytes([System.Drawing.Bitmap]$bitmap) {
  $stream = New-Object System.IO.MemoryStream
  try {
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    return $stream.ToArray()
  } finally {
    $stream.Dispose()
  }
}

$master = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
try {
  $frames = @()
  foreach ($size in $sizes) {
    $scaled = New-Scaled $master $size
    try {
      $bytes = if ($pngSizes -contains $size) {
        Get-PngBytes $scaled
      } else {
        Get-DibBytes $scaled
      }
      $frames += [pscustomobject]@{ Size = $size; Bytes = $bytes }
    } finally {
      $scaled.Dispose()
    }
  }
} finally {
  $master.Dispose()
}

$out = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($out)
try {
  $writer.Write([uint16]0)
  $writer.Write([uint16]1)
  $writer.Write([uint16]$frames.Count)
  $offset = 6 + 16 * $frames.Count
  foreach ($frame in $frames) {
    $dimension = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
    $writer.Write([byte]$dimension)
    $writer.Write([byte]$dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$frame.Bytes.Length)
    $writer.Write([uint32]$offset)
    $offset += $frame.Bytes.Length
  }
  foreach ($frame in $frames) {
    $writer.Write($frame.Bytes, 0, $frame.Bytes.Length)
  }
  $writer.Flush()
  $data = $out.ToArray()
} finally {
  $writer.Dispose()
  $out.Dispose()
}

foreach ($target in $targets) {
  [System.IO.File]::WriteAllBytes($target, $data)
  Write-Host "wrote $target ($($data.Length) bytes)"
}

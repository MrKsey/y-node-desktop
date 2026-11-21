#!/usr/bin/env bash
# Builds Y-Node Desktop on macOS.
#
#   ./scripts/build-macos.sh [version]
#
# The core is built for the architecture of the machine (arm64 or amd64) and
# placed into Contents/MacOS next to the application binary, which is where the
# window looks for it. The bundle is signed ad hoc, so it runs locally without
# an Apple developer account. Besides the .app in dist/macos, the script writes
# a .pkg installer that puts the app into /Applications for every user.
set -euo pipefail

version="${1:-1.0.0}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/app"
core="$root/core"

echo "==> building the core"
(
  cd "$core"
  CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=$version" \
    -o bin/y-node-core ./cmd/y-node-core
)

echo "==> building the window"
(
  cd "$app"
  flutter build macos --release
)

bundle="$(find "$app/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$bundle" ]]; then
  echo "the .app bundle was not produced" >&2
  exit 1
fi

echo "==> embedding the core"
cp "$core/bin/y-node-core" "$bundle/Contents/MacOS/y-node-core"
chmod +x "$bundle/Contents/MacOS/y-node-core"

echo "==> signing (ad hoc)"
codesign --force --deep --sign - "$bundle"

case "$(uname -m)" in
  x86_64) arch="x64" ;;
  arm64) arch="arm64" ;;
  *) arch="$(uname -m)" ;;
esac

dist="$root/dist/macos"
rm -rf "$dist"
mkdir -p "$dist"
cp -R "$bundle" "$dist/"

echo "==> building the .pkg installer"
pkgroot="$root/dist/pkgroot"
rm -rf "$pkgroot"
mkdir -p "$pkgroot"
cp -R "$bundle" "$pkgroot/"
pkg="$root/dist/y-node-desktop-$version-macos-$arch.pkg"
pkgbuild --root "$pkgroot" \
  --identifier "com.y-node.desktop" \
  --version "$version" \
  --install-location "/Applications" \
  "$pkg"
rm -rf "$pkgroot"

echo "Done: $dist/$(basename "$bundle")"
echo "Done: $pkg"

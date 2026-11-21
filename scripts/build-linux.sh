#!/usr/bin/env bash
# Builds Y-Node Desktop on Linux.
#
#   ./scripts/build-linux.sh [version]
#
# Produces dist/linux/y-node-desktop with the core binary next to the
# application binary, a tarball of the same directory and, when dpkg-deb is
# available, a .deb package that installs the app into /opt with a menu entry.
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
  flutter build linux --release
)

bundle="$app/build/linux/x64/release/bundle"
if [[ ! -d "$bundle" ]]; then
  echo "the bundle was not produced: $bundle" >&2
  exit 1
fi

echo "==> embedding the core"
cp "$core/bin/y-node-core" "$bundle/y-node-core"
chmod +x "$bundle/y-node-core"

# The window and the tray use the same icon as the Android app. The .desktop
# file is meant for a system-wide install (copy the directory to /opt and the
# desktop file to /usr/share/applications); the tarball keeps it next to the
# binary so a package builder can pick it up.
cp "$app/assets/tray_icon.png" "$bundle/y-node-desktop.png"
cat > "$bundle/y-node-desktop.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Y-Node
Comment=Yggdrasil client with a local proxy
Exec=y-node-desktop
Icon=y-node-desktop
Terminal=false
Categories=Network;
EOF

dist="$root/dist/linux"
rm -rf "$dist"
mkdir -p "$dist"
cp -R "$bundle" "$dist/y-node-desktop"
tar -C "$dist" -czf "$root/dist/y-node-desktop-$version-linux-x64.tar.gz" y-node-desktop

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "dpkg-deb is not available; skipping the .deb package"
  echo "Done: $dist/y-node-desktop"
  exit 0
fi

echo "==> building the .deb package"
arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
case "$arch" in
  amd64) artifact_arch="x64" ;;
  arm64) artifact_arch="arm64" ;;
  *) artifact_arch="$arch" ;;
esac
pkgroot="$root/dist/deb"
rm -rf "$pkgroot"
install -d "$pkgroot/DEBIAN" \
  "$pkgroot/opt/y-node-desktop" \
  "$pkgroot/usr/bin" \
  "$pkgroot/usr/share/applications" \
  "$pkgroot/usr/share/icons/hicolor/256x256/apps"
cp -R "$dist/y-node-desktop/." "$pkgroot/opt/y-node-desktop/"
ln -s /opt/y-node-desktop/y-node-desktop "$pkgroot/usr/bin/y-node-desktop"
cp "$app/assets/tray_icon.png" "$pkgroot/usr/share/icons/hicolor/256x256/apps/y-node-desktop.png"
cp "$bundle/y-node-desktop.desktop" "$pkgroot/usr/share/applications/y-node-desktop.desktop"
cat > "$pkgroot/DEBIAN/control" <<EOF
Package: y-node-desktop
Version: $version
Section: net
Priority: optional
Architecture: $arch
Maintainer: Y-Node <mrksey@yandex.ru>
Depends: libgtk-3-0, libblkid1, liblzma5
Description: Yggdrasil network client with a local HTTP and SOCKS5 proxy
 Y-Node Desktop runs a Yggdrasil node, exposes a local HTTP and SOCKS5 proxy
 and can switch the system proxy to that port.
EOF
dpkg-deb --build --root-owner-group "$pkgroot" \
  "$root/dist/y-node-desktop-$version-linux-$artifact_arch.deb"
rm -rf "$pkgroot"

echo "Done: $dist/y-node-desktop"

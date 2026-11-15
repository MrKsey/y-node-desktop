#!/usr/bin/env bash
# Builds Y-Node Desktop on Linux.
#
#   ./scripts/build-linux.sh [version]
#
# Produces dist/linux/y-node-desktop with the core binary next to the
# application binary, and a tarball of the same directory.
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

dist="$root/dist/linux"
rm -rf "$dist"
mkdir -p "$dist"
cp -R "$bundle" "$dist/y-node-desktop"
tar -C "$dist" -czf "$root/dist/y-node-desktop-$version-linux-x64.tar.gz" y-node-desktop
echo "Done: $dist/y-node-desktop"

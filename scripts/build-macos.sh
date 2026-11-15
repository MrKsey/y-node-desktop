#!/usr/bin/env bash
# Builds Y-Node Desktop on macOS.
#
#   ./scripts/build-macos.sh [version]
#
# The core is built for the architecture of the machine (arm64 or amd64) and
# placed into Contents/MacOS next to the application binary, which is where the
# window looks for it. The bundle is signed ad hoc, so it runs locally without
# an Apple developer account.
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

dist="$root/dist/macos"
rm -rf "$dist"
mkdir -p "$dist"
cp -R "$bundle" "$dist/"
echo "Done: $dist/$(basename "$bundle")"

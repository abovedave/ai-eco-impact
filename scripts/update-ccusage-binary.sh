#!/bin/bash
# Refreshes the vendored native ccusage binaries (Vendor/ccusage/darwin-{arm64,x64})
# from npm. These are real, standalone compiled executables published by the
# ccusage project itself as optional per-platform dependencies of the `ccusage`
# npm package (@ccusage/ccusage-darwin-arm64 / -darwin-x64) — this script just
# downloads and unpacks them; it does not compile anything.
#
# Usage: scripts/update-ccusage-binary.sh [version]
#   (defaults to the latest published version)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/ccusage"
VERSION="${1:-latest}"

if [ "$VERSION" = "latest" ]; then
	VERSION="$(npm view ccusage version)"
fi
echo "Fetching ccusage native binaries for v$VERSION..."

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

for ARCH_PAIR in "arm64:darwin-arm64" "x64:darwin-x64"; do
	NPM_ARCH="${ARCH_PAIR%%:*}"
	DIR_NAME="${ARCH_PAIR##*:}"
	echo "  - darwin-$NPM_ARCH"
	(cd "$WORKDIR" && npm pack "@ccusage/ccusage-darwin-$NPM_ARCH@$VERSION" --silent >/dev/null)
	TARBALL="$WORKDIR"/ccusage-ccusage-darwin-"$NPM_ARCH"-*.tgz
	tar xzf $TARBALL -C "$WORKDIR"
	mkdir -p "$VENDOR_DIR/$DIR_NAME"
	cp "$WORKDIR/package/bin/ccusage" "$VENDOR_DIR/$DIR_NAME/ccusage"
	chmod +x "$VENDOR_DIR/$DIR_NAME/ccusage"
	rm -rf "$WORKDIR/package" $TARBALL
done

# Keep the LICENSE fresh too (MIT, from the main `ccusage` package).
(cd "$WORKDIR" && npm pack "ccusage@$VERSION" --silent >/dev/null)
tar xzf "$WORKDIR"/ccusage-"$VERSION"*.tgz -C "$WORKDIR" 2>/dev/null || tar xzf "$WORKDIR"/ccusage-*.tgz -C "$WORKDIR"
cp "$WORKDIR/package/LICENSE" "$VENDOR_DIR/LICENSE"

echo "$VERSION" > "$VENDOR_DIR/VERSION"
echo "Updated $VENDOR_DIR to v$VERSION"

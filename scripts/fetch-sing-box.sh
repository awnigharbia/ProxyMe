#!/bin/bash
# Downloads the pinned sing-box release for both architectures, verifies the
# checksums and produces a universal binary at Vendor/sing-box.
set -euo pipefail

VERSION="1.14.2"
SHA_ARM64="925c5382eca8492b0150f868a6db20b18290a38700e621724b3703fd453e032d"
SHA_AMD64="b0bfb0dc70a5fc708710b9f5ea98b9ee76d40fa4169928d25d73edc4331df2fe"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
    local arch="$1" sha="$2"
    local name="sing-box-$VERSION-darwin-$arch"
    curl -fsSL -o "$TMP/$name.tar.gz" \
        "https://github.com/SagerNet/sing-box/releases/download/v$VERSION/$name.tar.gz"
    echo "$sha  $TMP/$name.tar.gz" | shasum -a 256 -c - >/dev/null
    tar -xzf "$TMP/$name.tar.gz" -C "$TMP"
    cp "$TMP/$name/LICENSE" "$TMP/LICENSE"
}

fetch arm64 "$SHA_ARM64"
fetch amd64 "$SHA_AMD64"

mkdir -p "$OUT"
lipo -create \
    "$TMP/sing-box-$VERSION-darwin-arm64/sing-box" \
    "$TMP/sing-box-$VERSION-darwin-amd64/sing-box" \
    -output "$OUT/sing-box"
chmod 755 "$OUT/sing-box"
cp "$TMP/LICENSE" "$OUT/sing-box-LICENSE"
echo "$VERSION" > "$OUT/sing-box-VERSION"
echo "sing-box $VERSION -> $OUT/sing-box ($(lipo -archs "$OUT/sing-box"))"

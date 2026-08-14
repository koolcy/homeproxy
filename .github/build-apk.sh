#!/bin/bash

set -e
set -o pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$BASE_DIR/.." && pwd)"

SDK_VERSION="25.12.1"

SDK_URL="https://downloads.immortalwrt.org/releases/${SDK_VERSION}/targets/x86/64/immortalwrt-sdk-${SDK_VERSION}-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"

SDK_DIR="$BASE_DIR/immortalwrt-sdk"
SDK_ARCHIVE="$BASE_DIR/immortalwrt-sdk.tar.zst"

OUTPUT_DIR="$BASE_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo " ImmortalWrt ${SDK_VERSION}"
echo " Build HomeProxy APK"
echo "========================================"

echo "PKG_DIR    : $PKG_DIR"
echo "SDK_DIR    : $SDK_DIR"

# --------------------------------------------------
# Download SDK
# --------------------------------------------------

if [ ! -f "$SDK_ARCHIVE" ]; then
    echo "===== Download ImmortalWrt SDK ====="

    curl -fL --retry 3 \
        -o "$SDK_ARCHIVE" \
        "$SDK_URL"
fi

# --------------------------------------------------
# Extract SDK
# --------------------------------------------------

if [ ! -d "$SDK_DIR" ]; then
    echo "===== Extract SDK ====="

    mkdir -p "$SDK_DIR"

    tar \
        --zstd \
        -xf "$SDK_ARCHIVE" \
        --strip-components=1 \
        -C "$SDK_DIR"
fi

cd "$SDK_DIR"

echo "===== SDK ready ====="

# --------------------------------------------------
# Prepare package
# --------------------------------------------------

echo "===== Prepare HomeProxy package ====="

rm -rf package/luci-app-homeproxy

mkdir -p package/luci-app-homeproxy

cp "$PKG_DIR/Makefile" \
    package/luci-app-homeproxy/

cp -a "$PKG_DIR/htdocs" \
    package/luci-app-homeproxy/

cp -a "$PKG_DIR/root" \
    package/luci-app-homeproxy/

cp -a "$PKG_DIR/po" \
    package/luci-app-homeproxy/

# --------------------------------------------------
# Feeds
# --------------------------------------------------

echo "===== Update feeds ====="

./scripts/feeds update -a

./scripts/feeds install -a

# --------------------------------------------------
# Enable APK
# --------------------------------------------------

echo "===== Enable APK package format ====="

cat > .config <<'EOF'
CONFIG_USE_APK=y
EOF

make defconfig

# --------------------------------------------------
# Build
# --------------------------------------------------

echo "===== Build HomeProxy ====="

make package/luci-app-homeproxy/compile V=s

# --------------------------------------------------
# Find APK
# --------------------------------------------------

echo "===== Find generated APK ====="

find bin/packages \
    -type f \
    -name 'luci-app-homeproxy*.apk' \
    -print

APK_FILE="$(find bin/packages \
    -type f \
    -name 'luci-app-homeproxy*.apk' \
    | head -n 1)"

if [ -z "$APK_FILE" ]; then
    echo "ERROR: HomeProxy APK was not generated!"
    exit 1
fi

echo "===== APK found ====="

echo "$APK_FILE"

# --------------------------------------------------
# Copy output
# --------------------------------------------------

rm -f "$OUTPUT_DIR"/*.apk

cp "$APK_FILE" "$OUTPUT_DIR/"

echo "===== Final APK ====="

ls -lah "$OUTPUT_DIR"/*.apk

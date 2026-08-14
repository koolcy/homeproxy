#!/bin/bash

set -e
set -o pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$BASE_DIR/.." && pwd)"

SDK_VERSION="25.12.1"

SDK_URL="https://downloads.immortalwrt.org/releases/${SDK_VERSION}/targets/x86/64/"

SDK_DIR="$BASE_DIR/immortalwrt-sdk"
SDK_ARCHIVE="$BASE_DIR/immortalwrt-sdk.tar.zst"
OUTPUT_DIR="$BASE_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo " ImmortalWrt ${SDK_VERSION}"
echo " Build HomeProxy APK"
echo "========================================"

# ========================================
# Download SDK
# ========================================

if [ ! -f "$SDK_ARCHIVE" ]; then
    echo "===== Download ImmortalWrt SDK ====="

    echo "SDK URL:"
    echo "$SDK_URL"

    exit 1
fi

# ========================================
# Extract SDK
# ========================================

if [ ! -d "$SDK_DIR" ]; then
    mkdir -p "$SDK_DIR"

    tar \
        --zstd \
        -xf "$SDK_ARCHIVE" \
        --strip-components=1 \
        -C "$SDK_DIR"
fi

cd "$SDK_DIR"

# ========================================
# Prepare package
# ========================================

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

# ========================================
# Build po2lmo
# ========================================

echo "===== Build po2lmo ====="

rm -rf "$BASE_DIR/po2lmo"

git clone \
    --filter=blob:none \
    --no-checkout \
    "https://github.com/openwrt/luci.git" \
    "$BASE_DIR/po2lmo"

pushd "$BASE_DIR/po2lmo"

git config core.sparseCheckout true

echo "modules/luci-base/src" \
    > ".git/info/sparse-checkout"

git checkout

cd modules/luci-base/src

make po2lmo

mkdir -p \
    "$SDK_DIR/package/luci-app-homeproxy/root/usr/lib/lua/luci/i18n"

./po2lmo \
    "$PKG_DIR/po/zh_Hans/homeproxy.po" \
    "$SDK_DIR/package/luci-app-homeproxy/root/usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo"

popd

rm -rf "$BASE_DIR/po2lmo"

echo "===== Check Chinese translation ====="

ls -lh \
    "$SDK_DIR/package/luci-app-homeproxy/root/usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo"

# ========================================
# Update feeds
# ========================================

echo "===== Update feeds ====="

./scripts/feeds update -a

./scripts/feeds install -a

# ========================================
# Enable APK
# ========================================

echo "===== Enable APK ====="

echo "CONFIG_USE_APK=y" > .config

make defconfig

# ========================================
# Build
# ========================================

echo "===== Build HomeProxy ====="

make package/luci-app-homeproxy/compile V=s

# ========================================
# Find APK
# ========================================

echo "===== Find APK ====="

find bin/packages \
    -type f \
    -name "luci-app-homeproxy*.apk" \
    -print

APK_FILE="$(
    find bin/packages \
        -type f \
        -name "luci-app-homeproxy*.apk" \
        | head -n 1
)"

if [ -z "$APK_FILE" ]; then
    echo "ERROR: APK was not generated!"
    exit 1
fi

echo "===== APK ====="

echo "$APK_FILE"

rm -f "$OUTPUT_DIR"/*.apk

cp "$APK_FILE" "$OUTPUT_DIR/"

echo "===== Final output ====="

ls -lah "$OUTPUT_DIR"

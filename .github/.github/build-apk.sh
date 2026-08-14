#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only

set -e
set -o pipefail

BASE_DIR="$(cd "$(dirname "$0")"; pwd)"
PKG_DIR="$BASE_DIR/.."

export PKG_SOURCE_DATE_EPOCH="${PKG_SOURCE_DATE_EPOCH:-$(date +%s)}"

echo "========================================"
echo " Build HomeProxy APK"
echo "========================================"

echo "BASE_DIR: $BASE_DIR"
echo "PKG_DIR : $PKG_DIR"

mkdir -p "$BASE_DIR/sdk"
mkdir -p "$BASE_DIR/output"

cd "$BASE_DIR/sdk"

SDK_URL="https://downloads.openwrt.org/releases/25.12.0/targets/x86/64/openwrt-sdk-25.12.0-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst"

echo "===== Download OpenWrt 25.12 SDK ====="

if [ ! -f sdk.tar.zst ]; then
    curl -fL --retry 3 \
        -o sdk.tar.zst \
        "$SDK_URL"
fi

echo "===== Extract SDK ====="

if [ ! -d sdk ]; then
    mkdir -p sdk
    tar --zstd -xf sdk.tar.zst --strip-components=1 -C sdk
fi

cd sdk

echo "===== SDK information ====="

./staging_dir/host/bin/apk --version || true

echo "===== Prepare HomeProxy package ====="

mkdir -p package/luci-app-homeproxy

rm -rf package/luci-app-homeproxy/*

cp -a "$PKG_DIR/Makefile" \
    package/luci-app-homeproxy/

cp -a "$PKG_DIR/htdocs" \
    package/luci-app-homeproxy/

cp -a "$PKG_DIR/root" \
    package/luci-app-homeproxy/

cp -a "$PKG_DIR/po" \
    package/luci-app-homeproxy/

echo "===== Update feeds ====="

./scripts/feeds update luci

./scripts/feeds install -a

echo "===== Configure APK package format ====="

cat > .config <<'EOF'
CONFIG_USE_APK=y
EOF

make defconfig

echo "===== Build HomeProxy ====="

make package/luci-app-homeproxy/compile V=s

echo "===== Find APK ====="

find bin/packages -type f -name "luci-app-homeproxy*.apk" -print

APK_FILE="$(find bin/packages -type f -name "luci-app-homeproxy*.apk" | head -n 1)"

if [ -z "$APK_FILE" ]; then
    echo "ERROR: APK was not generated!"
    exit 1
fi

echo "Found APK:"
echo "$APK_FILE"

cp "$APK_FILE" "$BASE_DIR/output/"

echo "===== APK output ====="

ls -lah "$BASE_DIR/output/"

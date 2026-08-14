#!/bin/bash

set -e
set -o pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$BASE_DIR/.." && pwd)"

SDK_VERSION="25.12.1"
TARGET="x86/64"

SDK_BASE_URL="https://downloads.immortalwrt.org/releases/${SDK_VERSION}/targets/${TARGET}"

SDK_DIR="$BASE_DIR/immortalwrt-sdk"
SDK_ARCHIVE="$BASE_DIR/immortalwrt-sdk.tar.zst"
OUTPUT_DIR="$BASE_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo " ImmortalWrt ${SDK_VERSION}"
echo " Target: ${TARGET}"
echo " Build HomeProxy APK"
echo "========================================"

# =========================================================
# Find SDK
# =========================================================

echo "===== Find ImmortalWrt SDK ====="

SDK_FILE="$(
    curl -fsSL "$SDK_BASE_URL/" |
    grep -oE 'href="[^"]*sdk[^"]*\.tar\.(zst|xz|gz)"' |
    sed 's/^href="//;s/"$//' |
    head -n 1
)"

if [ -z "$SDK_FILE" ]; then
    echo "ERROR: Cannot find ImmortalWrt SDK!"
    echo "URL: $SDK_BASE_URL/"
    exit 1
fi

echo "SDK file: $SDK_FILE"

SDK_URL="${SDK_BASE_URL}/${SDK_FILE}"

echo "SDK URL:"
echo "$SDK_URL"

# =========================================================
# Download SDK
# =========================================================

if [ ! -f "$SDK_ARCHIVE" ]; then
    echo "===== Download SDK ====="

    curl -fL --retry 5 --retry-delay 3 \
        -o "$SDK_ARCHIVE" \
        "$SDK_URL"
else
    echo "===== SDK archive already exists ====="
fi

# =========================================================
# Extract SDK
# =========================================================

if [ ! -d "$SDK_DIR" ]; then
    echo "===== Extract SDK ====="

    mkdir -p "$SDK_DIR"

    case "$SDK_ARCHIVE" in
        *.tar.zst)
            tar \
                --zstd \
                -xf "$SDK_ARCHIVE" \
                --strip-components=1 \
                -C "$SDK_DIR"
            ;;

        *.tar.xz)
            tar \
                -xJf "$SDK_ARCHIVE" \
                --strip-components=1 \
                -C "$SDK_DIR"
            ;;

        *.tar.gz)
            tar \
                -xzf "$SDK_ARCHIVE" \
                --strip-components=1 \
                -C "$SDK_DIR"
            ;;

        *)
            echo "ERROR: Unknown SDK archive format!"
            exit 1
            ;;
    esac
fi

cd "$SDK_DIR"

echo "===== SDK ready ====="

# =========================================================
# Prepare package
# =========================================================

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

# =========================================================
# Build Chinese translation
# =========================================================

echo "===== Build Chinese translation ====="

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

echo "===== Chinese translation ====="

ls -lh \
    "$SDK_DIR/package/luci-app-homeproxy/root/usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo"

# =========================================================
# Feeds
# =========================================================

echo "===== Update feeds ====="

./scripts/feeds update -a

./scripts/feeds install -a

# =========================================================
# Configure APK
# =========================================================

echo "===== Enable APK ====="

cat > .config <<'EOF'
CONFIG_USE_APK=y
EOF

make defconfig

# =========================================================
# Build
# =========================================================

echo "===== Build HomeProxy ====="

make package/luci-app-homeproxy/compile V=s

# =========================================================
# Find APK
# =========================================================

echo "===== Find generated APK ====="

find bin/packages \
    -type f \
    -name "luci-app-homeproxy*.apk" \
    -print

APK_FILE="$(
    find bin/packages \
        -type f \
        -name "luci-app-homeproxy*.apk" |
    head -n 1
)"

if [ -z "$APK_FILE" ]; then
    echo "ERROR: HomeProxy APK was not generated!"
    exit 1
fi

echo "Found APK:"
echo "$APK_FILE"

# =========================================================
# Copy output
# =========================================================

rm -f "$OUTPUT_DIR"/*.apk

cp "$APK_FILE" "$OUTPUT_DIR/"

echo "========================================"
echo " Final APK"
echo "========================================"

ls -lah "$OUTPUT_DIR"/*.apk

echo "========================================"
echo " APK manifest"
echo "========================================"

if command -v apk >/dev/null 2>&1; then
    apk manifest "$OUTPUT_DIR"/*.apk || true
fi

#!/bin/bash

set -e
set -o pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$BASE_DIR/.." && pwd)"

IMMORTALWRT_VERSION="25.12.1"
TARGET="x86/64"

SINGBOX_VERSION="1.11.15"

SDK_BASE_URL="https://downloads.immortalwrt.org/releases/${IMMORTALWRT_VERSION}/targets/${TARGET}"

SDK_DIR="$BASE_DIR/immortalwrt-sdk"
SDK_ARCHIVE="$BASE_DIR/immortalwrt-sdk.tar.zst"

OUTPUT_DIR="$BASE_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "=============================================="
echo " ImmortalWrt ${IMMORTALWRT_VERSION}"
echo " Target: ${TARGET}"
echo " sing-box: ${SINGBOX_VERSION}"
echo " Build: HomeProxy APK"
echo "=============================================="

# =========================================================
# 1. Find SDK
# =========================================================

echo
echo "===== Find ImmortalWrt SDK ====="

SDK_FILE="$(
    curl -fsSL "$SDK_BASE_URL/" |
    grep -oE 'immortalwrt-sdk-[^"]+\.tar\.zst' |
    head -n 1
)"

if [ -z "$SDK_FILE" ]; then
    echo "ERROR: Cannot find SDK"
    echo "URL: $SDK_BASE_URL/"
    exit 1
fi

echo "SDK:"
echo "$SDK_FILE"

SDK_URL="${SDK_BASE_URL}/${SDK_FILE}"

# =========================================================
# 2. Download SDK
# =========================================================

if [ ! -f "$SDK_ARCHIVE" ]; then

    echo
    echo "===== Download SDK ====="

    curl -fL \
        --retry 5 \
        --retry-delay 5 \
        -o "$SDK_ARCHIVE" \
        "$SDK_URL"

else

    echo
    echo "===== SDK already downloaded ====="

fi

# =========================================================
# 3. Extract SDK
# =========================================================

if [ ! -d "$SDK_DIR/include" ]; then

    echo
    echo "===== Extract SDK ====="

    rm -rf "$SDK_DIR"

    mkdir -p "$SDK_DIR"

    tar \
        --zstd \
        -xf "$SDK_ARCHIVE" \
        --strip-components=1 \
        -C "$SDK_DIR"

fi

cd "$SDK_DIR"

echo
echo "SDK directory:"
pwd

# =========================================================
# 4. Prepare feeds
# =========================================================

echo
echo "===== Update feeds ====="

./scripts/feeds update -a
./scripts/feeds install -a

# =========================================================
# 5. Add sing-box 1.11.15 package
# =========================================================

echo
echo "=============================================="
echo " Build sing-box ${SINGBOX_VERSION}"
echo "=============================================="

rm -rf package/sing-box

mkdir -p package/sing-box

cat > package/sing-box/Makefile <<EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=${SINGBOX_VERSION}
PKG_RELEASE:=1

PKG_SOURCE:=sing-box-\$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/SagerNet/sing-box/tar.gz/v\$(PKG_VERSION)
PKG_HASH:=skip

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/sagernet/sing-box
GO_PKG_BUILD_PKG:=\$(GO_PKG)/cmd/sing-box
GO_PKG_LDFLAGS_X:=\$(GO_PKG)/constant.Version=\$(PKG_VERSION)

include \$(INCLUDE_DIR)/package.mk
include \$(INCLUDE_DIR)/../feeds/packages/lang/golang/golang-package.mk

define Package/sing-box

  SECTION:=net
  CATEGORY:=Network
  TITLE:=The universal proxy platform
  URL:=https://sing-box.sagernet.org

  DEPENDS:=+ca-bundle +kmod-inet-diag +kmod-tun

endef

define Package/sing-box/description
Sing-box is a universal proxy platform.
endef

GO_PKG_TAGS:=with_acme,with_clash_api,with_dhcp,with_gvisor,with_quic,with_tailscale,with_utls,with_wireguard

define Package/sing-box/install

	\$(INSTALL_DIR) \$1/usr/bin

	\$(INSTALL_BIN) \$(GO_PKG_BUILD_BIN_DIR)/sing-box \
		\$1/usr/bin/sing-box

endef

\$(eval \$(call BuildPackage,sing-box))
EOF

echo
echo "===== sing-box Makefile ====="

cat package/sing-box/Makefile

# =========================================================
# 6. Download sing-box source
# =========================================================

echo
echo "===== Download sing-box source ====="

make package/sing-box/download V=s

# =========================================================
# 7. Compile sing-box
# =========================================================

echo
echo "===== Compile sing-box ${SINGBOX_VERSION} ====="

make package/sing-box/compile V=s -j2

# =========================================================
# 8. Find sing-box APK
# =========================================================

echo
echo "===== Find sing-box APK ====="

find bin/packages \
    -type f \
    -name "sing-box*.apk" \
    -print

SINGBOX_APK="$(
    find bin/packages \
        -type f \
        -name "sing-box*.apk" |
    head -n 1
)"

if [ -z "$SINGBOX_APK" ]; then
    echo "ERROR: sing-box APK was not generated!"
    exit 1
fi

echo
echo "Found:"
echo "$SINGBOX_APK"

# =========================================================
# 9. Prepare HomeProxy
# =========================================================

echo
echo "=============================================="
echo " Prepare HomeProxy"
echo "=============================================="

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
# 10. Build Chinese translation
# =========================================================

echo
echo "===== Build Chinese translation ====="

rm -rf "$BASE_DIR/po2lmo"

git clone \
    --filter=blob:none \
    --no-checkout \
    https://github.com/openwrt/luci.git \
    "$BASE_DIR/po2lmo"

pushd "$BASE_DIR/po2lmo"

git config core.sparseCheckout true

echo "modules/luci-base/src" \
    > .git/info/sparse-checkout

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

echo
echo "Chinese translation generated:"

ls -lh \
    "$SDK_DIR/package/luci-app-homeproxy/root/usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo"

# =========================================================
# 11. Configure APK
# =========================================================

echo
echo "===== Configure APK build ====="

cat > .config <<EOF
CONFIG_USE_APK=y
CONFIG_PACKAGE_luci-app-homeproxy=m
CONFIG_PACKAGE_sing-box=m
EOF

make defconfig

# =========================================================
# 12. Compile HomeProxy
# =========================================================

echo
echo "=============================================="
echo " Compile HomeProxy"
echo "=============================================="

make package/luci-app-homeproxy/compile V=s -j2

# =========================================================
# 13. Find HomeProxy APK
# =========================================================

echo
echo "===== Find HomeProxy APK ====="

find bin/packages \
    -type f \
    -name "luci-app-homeproxy*.apk" \
    -print

HOMEProxy_APK="$(
    find bin/packages \
        -type f \
        -name "luci-app-homeproxy*.apk" |
    head -n 1
)"

if [ -z "$HOMEProxy_APK" ]; then
    echo
    echo "ERROR: HomeProxy APK was not generated!"
    exit 1
fi

# =========================================================
# 14. Output
# =========================================================

echo
echo "===== Prepare output ====="

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cp "$HOMEProxy_APK" "$OUTPUT_DIR/"

cp "$SINGBOX_APK" "$OUTPUT_DIR/"

echo
echo "=============================================="
echo " BUILD SUCCESS"
echo "=============================================="

ls -lah "$OUTPUT_DIR"

echo
echo "APK files:"

find "$OUTPUT_DIR" \
    -type f \
    -name "*.apk" \
    -print

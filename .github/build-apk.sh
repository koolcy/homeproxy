#!/bin/bash

set -e
set -o pipefail

export TERM=xterm
export LC_ALL=C

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
echo " Build HomeProxy APK"
echo "=============================================="

# =========================================================
# 1. Find SDK
# =========================================================

echo
echo "===== Find ImmortalWrt SDK ====="

SDK_FILE="$(
    curl -fsSL "$SDK_BASE_URL/" |
    grep -oE 'href="[^"]*sdk[^"]*\.tar\.zst"' |
    sed 's/^href="//;s/"$//' |
    head -n 1
)"

if [ -z "$SDK_FILE" ]; then
    echo "ERROR: Cannot find ImmortalWrt SDK"
    echo "URL: $SDK_BASE_URL/"
    exit 1
fi

SDK_URL="${SDK_BASE_URL}/${SDK_FILE}"

echo "SDK file:"
echo "$SDK_FILE"

# =========================================================
# 2. Download SDK
# =========================================================

if [ ! -f "$SDK_ARCHIVE" ]; then

    echo
    echo "===== Download SDK ====="

    curl -fL \
        --retry 5 \
        --retry-delay 3 \
        -o "$SDK_ARCHIVE" \
        "$SDK_URL"

fi

# =========================================================
# 3. Extract SDK
# =========================================================

if [ ! -f "$SDK_DIR/include/toplevel.mk" ]; then

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
echo "SDK:"
pwd

# =========================================================
# 4. Update feeds
#
# IMPORTANT:
# Do NOT use:
#
#   ./scripts/feeds install -a
#
# It can introduce thousands of Kconfig symbols and
# recursive dependencies.
# =========================================================

echo
echo "===== Update required feeds ====="

./scripts/feeds update luci
./scripts/feeds update packages

# =========================================================
# 5. Install only required packages
# =========================================================

echo
echo "===== Install required feed packages ====="

./scripts/feeds install luci-base
./scripts/feeds install luci-compat
./scripts/feeds install firewall4
./scripts/feeds install chinadns-ng
./scripts/feeds install kmod-nft-tproxy

# =========================================================
# 6. Create sing-box package
# =========================================================

echo
echo "=============================================="
echo " Prepare sing-box ${SINGBOX_VERSION}"
echo "=============================================="

rm -rf package/sing-box

mkdir -p package/sing-box

cat > package/sing-box/Makefile <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=1.11.15
PKG_RELEASE:=1

PKG_SOURCE:=sing-box-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/SagerNet/sing-box/tar.gz/v$(PKG_VERSION)
PKG_HASH:=skip

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

GO_PKG:=github.com/sagernet/sing-box
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/sing-box
GO_PKG_LDFLAGS_X:=$(GO_PKG)/constant.Version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/../feeds/packages/lang/golang/golang-package.mk

define Package/sing-box
  SECTION:=net
  CATEGORY:=Network
  TITLE:=The universal proxy platform
  URL:=https://sing-box.sagernet.org
  DEPENDS:=+ca-bundle +kmod-tun
endef

define Package/sing-box/description
Sing-box universal proxy platform.
endef

GO_PKG_TAGS:=with_acme,with_clash_api,with_dhcp,with_gvisor,with_quic,with_tailscale,with_utls,with_wireguard

define Package/sing-box/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/sing-box \
		$(1)/usr/bin/sing-box
endef

$(eval $(call BuildPackage,sing-box))
EOF

# =========================================================
# 7. Prepare HomeProxy
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
# 8. Chinese translation
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
echo "Chinese translation:"
ls -lh \
    "$SDK_DIR/package/luci-app-homeproxy/root/usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo"

# =========================================================
# 9. Prepare minimal config
# =========================================================

echo
echo "===== Prepare minimal SDK configuration ====="

rm -f .config

cat > .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_ROOTFS_TARGZ=y

CONFIG_PACKAGE_luci-app-homeproxy=m
CONFIG_PACKAGE_sing-box=m

CONFIG_PACKAGE_luci-base=m
CONFIG_PACKAGE_luci-compat=m

CONFIG_PACKAGE_firewall4=m
CONFIG_PACKAGE_chinadns-ng=m
CONFIG_PACKAGE_kmod-nft-tproxy=m
EOF

# IMPORTANT:
# Use defconfig only after limiting the package set.
make defconfig

# =========================================================
# 10. Compile sing-box
# =========================================================

echo
echo "=============================================="
echo " Compile sing-box ${SINGBOX_VERSION}"
echo "=============================================="

make package/sing-box/download V=s

make package/sing-box/compile \
    V=s \
    -j2

# =========================================================
# 11. Compile HomeProxy
# =========================================================

echo
echo "=============================================="
echo " Compile HomeProxy"
echo "=============================================="

make package/luci-app-homeproxy/compile \
    V=s \
    -j2

# =========================================================
# 12. Find APK
# =========================================================

echo
echo "===== Find APK ====="

find bin/packages \
    -type f \
    \( \
        -name "sing-box*.apk" \
        -o \
        -name "luci-app-homeproxy*.apk" \
    \) \
    -print

SINGBOX_APK="$(
    find bin/packages \
        -type f \
        -name "sing-box*.apk" |
    head -n 1
)"

HOMEProxy_APK="$(
    find bin/packages \
        -type f \
        -name "luci-app-homeproxy*.apk" |
    head -n 1
)"

if [ -z "$SINGBOX_APK" ]; then
    echo "ERROR: sing-box APK not found!"
    exit 1
fi

if [ -z "$HOMEProxy_APK" ]; then
    echo "ERROR: HomeProxy APK not found!"
    exit 1
fi

# =========================================================
# 13. Output
# =========================================================

echo
echo "===== Prepare output ====="

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cp "$SINGBOX_APK" "$OUTPUT_DIR/"
cp "$HOMEProxy_APK" "$OUTPUT_DIR/"

echo
echo "=============================================="
echo " BUILD SUCCESS"
echo "=============================================="

ls -lah "$OUTPUT_DIR"

echo
echo "Generated APK:"
find "$OUTPUT_DIR" -type f -name "*.apk" -print

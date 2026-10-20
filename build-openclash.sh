#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=/home/ub/ps5-openwrt-13.00
cd "$ROOT"
test "$(id -u)" != 0
trap 'rc=$?; printf "%s\n" "$rc" > "$ROOT/logs/openclash-build.exit"' EXIT
test "$(git -C work/openclash-source rev-parse HEAD)" = e553e82e01c697aefbe1555261a503f425e00ccd
SDK="$ROOT/work/openwrt-sdk"
test ! -e "$SDK/package/luci-app-openclash" || test -L "$SDK/package/luci-app-openclash"
ln -sfn "$ROOT/work/openclash-source/luci-app-openclash" "$SDK/package/luci-app-openclash"
cd "$SDK"
./scripts/feeds install luci-compat
cat >>.config <<'EOF'
CONFIG_PACKAGE_luci-app-openclash=m
CONFIG_PACKAGE_luci-compat=m
CONFIG_PACKAGE_dnsmasq-full=m
CONFIG_PACKAGE_dnsmasq_full_nftset=y
# CONFIG_PACKAGE_dnsmasq is not set
# CONFIG_SIGNED_PACKAGES is not set
EOF
make defconfig
if ! test -x staging_dir/hostpkg/bin/po2lmo; then
    nice -n 10 make -j3 package/feeds/luci/luci-base/host/compile V=s
fi
# Runtime dependencies come from the signed matching release repositories.
# Compile this package directly with the SDK rather than rebuilding the SDK's
# stock kernel packages, which are not suitable for the PS5 kernel.
export PATH="$SDK/staging_dir/hostpkg/bin:$SDK/staging_dir/host/bin:$PATH"
nice -n 10 make -j3 -C "$SDK/package/luci-app-openclash" TOPDIR="$SDK" compile V=s
find bin/packages -name 'luci-app-openclash-*.apk' -exec cp -t "$ROOT/output/openclash/" {} +
test "$(find "$ROOT/output/openclash" -name 'luci-app-openclash-*.apk' | wc -l)" = 1
echo 'OpenClash SDK build complete.'

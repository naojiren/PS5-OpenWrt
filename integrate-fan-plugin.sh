#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" = 0
test "$(cat logs/fan-build.exit)" = 0
if ! test -f work/revisions/pre-fan/.snapshot-complete; then
    test ! -d work/revisions/pre-fan || { echo 'Incomplete pre-fan snapshot needs inspection'; exit 1; }
    mkdir -p work/revisions/pre-fan
    cp -a --reflink=auto output work/revisions/pre-fan/output
    (cd work/revisions/pre-fan/output && sha256sum -c SHA256SUMS)
    touch work/revisions/pre-fan/.snapshot-complete
fi
package=output/fan/luci-app-ps5-fan-1.0.0-r1.apk
cp work/openwrt-sdk/bin/packages/x86_64/base/luci-app-ps5-fan-1.0.0-r1.apk "$package"
work/openwrt-sdk/staging_dir/host/bin/apk adbsign --allow-untrusted --sign-key private/apk-signing.pem "$package"
cp "$package" work/rootfs/tmp/
chroot work/rootfs /usr/bin/apk verify /tmp/luci-app-ps5-fan-1.0.0-r1.apk
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add /tmp/luci-app-ps5-fan-1.0.0-r1.apk
rm -f work/rootfs/tmp/luci-app-ps5-fan-1.0.0-r1.apk
mkdir -p work/rootfs/tmp/lock
chroot work/rootfs /etc/init.d/ps5-fan enable
chroot work/rootfs /sbin/uci -q set ps5_fan.main.mode=auto
chroot work/rootfs /sbin/uci -q set ps5_fan.main.target=80
chroot work/rootfs /sbin/uci commit ps5_fan
test -x work/rootfs/usr/libexec/rpcd/ps5.fan
chroot work/rootfs /bin/sh -n /usr/libexec/ps5-fanctl
chroot work/rootfs /bin/sh -n /usr/libexec/rpcd/ps5.fan
chroot work/rootfs /bin/sh -n /etc/init.d/ps5-fan
cp README-zh-CN.md output/README-zh-CN.md
rm -f output/ps5-openwrt-25.12.6-13xx-experimental.img output/ps5-openwrt-25.12.6-13xx-experimental.img.xz output/validation-vm.json output/image-before-test.sha256
chown -R ub:ub output
echo '=== FAN PLUGIN INTEGRATED ==='

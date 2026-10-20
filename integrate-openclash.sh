#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=/home/ub/ps5-openwrt-13.00
cd "$ROOT"
test "$(id -u)" = 0
test "$(cat logs/openclash-build.exit)" = 0
test -f work/revisions/pre-openclash-20261020/.snapshot-complete
APK=work/openwrt-sdk/staging_dir/host/bin/apk
openclash=$(find output/openclash -maxdepth 1 -name 'luci-app-openclash-*.apk')
test -f "$openclash"
"$APK" adbsign --allow-untrusted --sign-key private/apk-signing.pem "$openclash"
chown -R root:root work/mihomo-package work/openclash-support-package
"$APK" mkpkg --files work/mihomo-package --info name:mihomo --info version:1.19.32-r1 \
    --info arch:x86_64 --info 'description:Mihomo Meta core preinstalled for OpenClash on PS5' \
    --info license:GPL-3.0-only --info 'url:https://github.com/MetaCubeX/mihomo' \
    --sign-key private/apk-signing.pem --output output/openclash/mihomo-1.19.32-r1.apk
cp "$openclash" output/openclash/mihomo-1.19.32-r1.apk work/rootfs/tmp/openclash-offline/ps5/
"$APK" --allow-untrusted mkndx --sign-key private/apk-signing.pem \
    --output work/rootfs/tmp/openclash-offline/ps5/packages.adb work/rootfs/tmp/openclash-offline/ps5/*.apk
repos=()
for path in work/rootfs/tmp/openclash-offline/*/packages.adb; do
    relative=${path#work/rootfs}
    chroot work/rootfs /usr/bin/apk verify "$relative"
    repos+=(-X "file://$relative")
done
for path in work/rootfs/tmp/openclash-offline/ps5/*.apk; do
    chroot work/rootfs /usr/bin/apk verify "${path#work/rootfs}"
done
# Replace the explicitly selected small DNS package with its complete variant.
# The snapshot contains the entire previous root filesystem and deliverables.
cp work/rootfs/etc/apk/world work/revisions/pre-openclash-20261020/apk-world-before
sed -i '/^dnsmasq$/d' work/rootfs/etc/apk/world
chroot work/rootfs /usr/bin/apk --no-network --no-scripts "${repos[@]}" add \
    luci-app-openclash mihomo ps5-openclash-support luci-compat dnsmasq-full
chroot work/rootfs /sbin/uci set openclash.config.enable=0
chroot work/rootfs /sbin/uci set openclash.config.core_type=Meta
chroot work/rootfs /sbin/uci set openclash.config.core_version=linux-amd64-v1
chroot work/rootfs /sbin/uci set openclash.config.smart_enable=0
chroot work/rootfs /sbin/uci commit openclash
mkdir -p work/rootfs/tmp/lock
# The service remains available after importing a configuration; no config is
# fabricated and transparent proxying is not enabled without a subscription.
chroot work/rootfs /etc/init.d/openclash enable
cp ps5-bridge-hardware-validation.json work/rootfs/usr/share/ps5-openwrt/
cp README-zh-CN.md output/README-zh-CN.md
python3 - <<'PY'
from pathlib import Path
import json,hashlib
p=Path('output/openclash/build-provenance.json');d=json.loads(p.read_text())
d['packages']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in p.parent.glob('*.apk')}
d['signed_with']='PS5 OpenWrt image APK RSA trust key'
d['full_dnsmasq']=True;d['firewall_backend']='nftables'
d['kernel_reused_after_hardware_validation']=True
p.write_text(json.dumps(d,indent=2)+'\n')
PY
chroot work/rootfs /usr/bin/apk list --installed kernel ps5-iw620 luci-app-openclash mihomo ps5-openclash-support dnsmasq-full luci-compat
test "$(chroot work/rootfs /sbin/uci get dhcp.lan.ignore)" = 1
test "$(chroot work/rootfs /sbin/uci get wireless.default_radio0.network)" = lan
test "$(sha256sum work/rootfs/lib/modules/7.1.7-ps5-openwrt/mts.ko | cut -d' ' -f1)" = 6311f35a077bc5993bb4faef608ed7371006ef369ea1903b5653a474aa315f7a
cmp work/revisions/pre-openclash-20261020/rootfs/etc/config/network work/rootfs/etc/config/network
cmp work/revisions/pre-openclash-20261020/rootfs/etc/config/wireless work/rootfs/etc/config/wireless
cmp work/revisions/pre-openclash-20261020/rootfs/bin/coremark work/rootfs/bin/coremark
# Only temporary offline repository files generated above are removed.
find work/rootfs/tmp/openclash-offline -type f -delete
rm -f output/ps5-openwrt-25.12.6-13xx-experimental.img output/ps5-openwrt-25.12.6-13xx-experimental.img.xz output/validation-vm.json output/image-before-test.sha256
chown -R ub:ub output
echo 'OpenClash, Mihomo and dependencies integrated with the validated MTS repair.'

#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/ub/ps5-openwrt-13.00
test "$(id -u)" = 0
BACKUP=work/revisions/pre-lan-ap-20261020
if ! test -f "$BACKUP/.snapshot-complete"; then
    test ! -e "$BACKUP"
    mkdir -p "$BACKUP"
    cp -a --reflink=auto output "$BACKUP/output"
    cp -a --reflink=auto work/rootfs "$BACKUP/rootfs"
    touch "$BACKUP/.snapshot-complete"
fi
(cd "$BACKUP/output" && sha256sum -c SHA256SUMS)
mkdir -p work/wifi-package/etc/{init.d,config} work/wifi-package/usr/share/ps5-openwrt
install -m 755 files/etc/init.d/ps5-wifi work/wifi-package/etc/init.d/ps5-wifi
install -m 644 files/etc/config/wireless work/wifi-package/etc/config/wireless
python3 - <<'PY'
import json
from pathlib import Path
p=Path('output/wifi/build-provenance.json')
d=json.loads(p.read_text())
d['revision']='7.1.7-r5'
d['startup_fixes']=['Detect NXP mwiphy0 radio name','Set configured regulatory domain before IW620 probe','Allow up to 30 seconds for radio initialization']
d['wireless_defaults']={'enabled':True,'mode':'ap','ssid':'PS5-OpenWrt','country':'CN','band':'5g','channel':36,'encryption':'none','network':'lan'}
d['radio_registration_verified_on_user_PS5']=True
d['ap_association_hardware_tested']=False
p.write_text(json.dumps(d,indent=2)+'\n')
Path('work/wifi-package/usr/share/ps5-openwrt/wifi-build-provenance.json').write_text(p.read_text())
PY
chown -R root:root work/wifi-package
work/openwrt-sdk/staging_dir/host/bin/apk mkpkg --files work/wifi-package \
    --info name:ps5-iw620 --info version:7.1.7-r5 --info arch:x86_64 \
    --info 'description:PS5 IW620 Wi-Fi with signed regulatory data and automatic CN channel 36 AP' \
    --info 'license:GPL-2.0-only AND ISC' \
    --info 'depends:kernel=7.1.7-r1003 block-mount iw iwinfo wpad-basic-mbedtls wifi-scripts wireless-regdb' \
    --info 'provides:kmod-cfg80211=7.1.7-r1003 kmod-mac80211=7.1.7-r1003' \
    --sign-key private/apk-signing.pem --output output/wifi/ps5-iw620-7.1.7-r5.apk
cp output/wifi/ps5-iw620-7.1.7-r5.apk output/kernel-7.1.7-r1003.apk work/rootfs/tmp/
chroot work/rootfs /usr/bin/apk verify /tmp/ps5-iw620-7.1.7-r5.apk /tmp/kernel-7.1.7-r1003.apk
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add /tmp/ps5-iw620-7.1.7-r5.apk /tmp/kernel-7.1.7-r1003.apk
rm work/rootfs/tmp/ps5-iw620-7.1.7-r5.apk work/rootfs/tmp/kernel-7.1.7-r1003.apk
install -m 644 files/etc/config/network files/etc/config/wireless work/rootfs/etc/config/
install -m 755 files/etc/uci-defaults/99-ps5 work/rootfs/etc/uci-defaults/99-ps5
install -m 755 files/etc/init.d/ps5-wifi work/rootfs/etc/init.d/ps5-wifi
install -m 644 files/etc/sysctl.d/95-ps5-bypass.conf work/rootfs/etc/sysctl.d/95-ps5-bypass.conf
for name in work/rootfs/etc/config/wireless.apk-new work/rootfs/etc/init.d/ps5-wifi.apk-new; do
    if test -f "$name"; then cmp "$name" "${name%.apk-new}"; rm "$name"; fi
done
mkdir -p work/rootfs/tmp/lock
chroot work/rootfs /etc/init.d/ps5-wifi enable
test "$(chroot work/rootfs /sbin/uci get network.lan.device)" = br-lan
test "$(chroot work/rootfs /sbin/uci get network.lan.proto)" = dhcp
test "$(chroot work/rootfs /sbin/uci get wireless.radio0.disabled)" = 0
test "$(chroot work/rootfs /sbin/uci get wireless.radio0.country)" = CN
test "$(chroot work/rootfs /sbin/uci get wireless.default_radio0.network)" = lan
test "$(chroot work/rootfs /sbin/uci get dhcp.lan.ignore)" = 1
cmp "$BACKUP/rootfs/bin/coremark" work/rootfs/bin/coremark
cp README-zh-CN.md output/README-zh-CN.md
rm -f output/wifi/ps5-iw620-7.1.7-r2.apk output/wifi/ps5-iw620-7.1.7-r3.apk output/wifi/ps5-iw620-7.1.7-r4.apk output/kernel-7.1.7-r1001.apk output/kernel-7.1.7-r1002.apk
rm -f output/ps5-openwrt-25.12.6-13xx-experimental.img output/ps5-openwrt-25.12.6-13xx-experimental.img.xz output/validation-vm.json output/image-before-test.sha256
chown -R ub:ub output
echo 'LAN bridge and automatic AP defaults integrated.'

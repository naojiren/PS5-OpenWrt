#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/ub/ps5-openwrt-13.00
test "$(id -u)" = 0
test "$(cat logs/coremark16-build.exit)" = 0
BACKUP=work/revisions/pre-wifi-coremark16-20261020
test -f "$BACKUP/.snapshot-complete"
(cd "$BACKUP/output" && sha256sum -c SHA256SUMS)
grep -Fx 'CONFIG_COREMARK_ENABLE_MULTITHREADING=y' work/openwrt-sdk/.config
grep -Fx 'CONFIG_COREMARK_NUMBER_OF_THREADS=16' work/openwrt-sdk/.config
packages=()
for package in output/extra-packages/*.apk; do
    work/openwrt-sdk/staging_dir/host/bin/apk adbsign --allow-untrusted --sign-key private/apk-signing.pem "$package"
    cp "$package" work/rootfs/tmp/
    packages+=("/tmp/$(basename "$package")")
    chroot work/rootfs /usr/bin/apk verify "/tmp/$(basename "$package")"
done
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add "${packages[@]}"
rm -f work/rootfs/tmp/coremark-*.apk work/rootfs/tmp/luci-theme-argon-*.apk
python3 - <<'PY'
import json,hashlib
from pathlib import Path
p=Path('output/extra-packages/build-provenance.json')
d=json.loads(p.read_text())
assert d['coremark_threads']==16 and d['coremark_multithreading']
d['packages']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in p.parent.glob('*.apk')}
d['signed_with']='PS5 OpenWrt image APK RSA trust key'
p.write_text(json.dumps(d,indent=2)+'\n')
PY
test -f output/wifi-fix-13.00/ps5-iw620-7.1.7-r2.apk
cp output/wifi-fix-13.00/ps5-iw620-7.1.7-r2.apk output/wifi/
cp output/wifi-fix-13.00/build-provenance.json output/wifi/build-provenance.json
cp loader-patches/13.00-wifi-offset.patch output/wifi/loader-wifi-fix.patch
# Keep only the new package in the published package directory. The previous
# complete output is retained in the checked revision snapshot above.
rm -f output/wifi/ps5-iw620-7.1.7-r1.apk
cp output/wifi/ps5-iw620-7.1.7-r2.apk work/rootfs/tmp/
chroot work/rootfs /usr/bin/apk verify /tmp/ps5-iw620-7.1.7-r2.apk
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add /tmp/ps5-iw620-7.1.7-r2.apk
rm work/rootfs/tmp/ps5-iw620-7.1.7-r2.apk
install -m 755 files/etc/init.d/ps5-wifi work/rootfs/etc/init.d/ps5-wifi
install -m 644 work/rootfs/usr/share/ps5-openwrt/regdb/regulatory.db work/rootfs/usr/share/ps5-openwrt/regdb/regulatory.db.p7s work/rootfs/lib/firmware/
cmp files/etc/init.d/ps5-wifi work/rootfs/etc/init.d/ps5-wifi
openssl cms -verify -binary -inform DER -in work/rootfs/lib/firmware/regulatory.db.p7s -content work/rootfs/lib/firmware/regulatory.db -noverify -out /dev/null
mkdir -p work/rootfs/tmp/lock
chroot work/rootfs /etc/init.d/ps5-wifi enable
chroot work/rootfs /usr/bin/apk list --installed coremark ps5-iw620 luci-app-ps5-fan
cmp files/etc/config/network work/rootfs/etc/config/network
test ! -f work/rootfs/lib/firmware/nxp/pcieuartiw620_combo_v1.bin
test ! -f work/rootfs/etc/init.d/ps5-wifi.apk-new
cp README-zh-CN.md output/README-zh-CN.md
rm -f output/ps5-openwrt-25.12.6-13xx-experimental.img output/ps5-openwrt-25.12.6-13xx-experimental.img.xz output/validation-vm.json output/image-before-test.sha256
chown -R ub:ub output
echo 'CoreMark16 and Wi-Fi fixes integrated; ready to create image.'

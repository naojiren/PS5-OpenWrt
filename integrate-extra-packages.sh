#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" = 0
test "$(cat logs/extra-packages.exit)" = 0
test -f work/.rootfs-packaged
BACKUP=work/revisions/pre-argon
if ! test -f "$BACKUP/.snapshot-complete"; then
    test ! -d "$BACKUP" || { echo 'Incomplete revision backup needs inspection'; exit 1; }
    mkdir -p "$BACKUP/private"
    chmod 700 "$BACKUP/private"
    cp -a --reflink=auto output "$BACKUP/output"
    cp -a --reflink=auto work/rootfs "$BACKUP/rootfs"
    cp -a private/root-password.txt "$BACKUP/private/"
    (cd "$BACKUP/output" && grep -v '  README-zh-CN.md$' SHA256SUMS | sha256sum -c - && sha256sum README-zh-CN.md > README.snapshot.sha256)
    touch "$BACKUP/.snapshot-complete"
fi
test ! -f README-zh-CN.md || cp README-zh-CN.md output/README-zh-CN.md
echo '=== Signing compiled extra packages with existing image trust key ==='
find work/openwrt-sdk/bin/packages -type f \( -name 'coremark-*.apk' -o -name 'luci-theme-argon-*.apk' \) -exec cp -t output/extra-packages/ {} +
packages=()
for package in output/extra-packages/*.apk; do
    work/openwrt-sdk/staging_dir/host/bin/apk adbsign --allow-untrusted --sign-key private/apk-signing.pem "$package"
    cp "$package" work/rootfs/tmp/
    packages+=("/tmp/$(basename "$package")")
    chroot work/rootfs /usr/bin/apk verify "/tmp/$(basename "$package")"
done
python3 - <<'PY'
import hashlib,json
from pathlib import Path
p=Path('output/extra-packages/build-provenance.json')
data=json.loads(p.read_text())
data['packages']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in p.parent.glob('*.apk')}
data['signed_with']='PS5 OpenWrt image APK RSA trust key'
p.write_text(json.dumps(data,indent=2)+'\n')
PY
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add "${packages[@]}"
rm -f work/rootfs/tmp/luci-theme-argon-*.apk work/rootfs/tmp/coremark-*.apk
echo '=== Installing RTL8156B firmware and checking matching kernel module ==='
test -f work/rootfs/lib/modules/7.1.7-ps5-openwrt/r8152.ko
modinfo work/rootfs/lib/modules/7.1.7-ps5-openwrt/r8152.ko > output/rtl8156-driver-info.txt
mkdir -p work/rootfs/lib/firmware/rtl_nic
for source in /usr/lib/firmware/rtl_nic/rtl815*.fw*; do
    test -f "$source" || continue
    filename=$(basename "$source")
    case "$filename" in
        *.zst) zstd -dcf "$source" > "work/rootfs/lib/firmware/rtl_nic/${filename%.zst}" ;;
        *.xz) xz -dcf "$source" > "work/rootfs/lib/firmware/rtl_nic/${filename%.xz}" ;;
        *) cp -L "$source" work/rootfs/lib/firmware/rtl_nic/ ;;
    esac
done
test -s work/rootfs/lib/firmware/rtl_nic/rtl8156b-2.fw
dpkg-query -S /usr/lib/firmware/rtl_nic/rtl8156b-2.fw.zst > output/rtl8156-firmware-source.txt
FW_PACKAGE=$(dpkg-query -S /usr/lib/firmware/rtl_nic/rtl8156b-2.fw.zst | cut -d: -f1)
cp "/usr/share/doc/$FW_PACKAGE/copyright" work/rootfs/lib/firmware/LICENSE.realtek-ubuntu
(cd work/rootfs/lib/firmware && sha256sum rtl_nic/rtl815*.fw) > output/rtl8156-firmware-sha256sums.txt
cp -a files/. work/rootfs/
chmod 755 work/rootfs/etc/uci-defaults/99-ps5 work/rootfs/etc/hotplug.d/net/95-ps5-redirects work/rootfs/etc/hotplug.d/iface/95-ps5-redirects
test "$(grep -cx r8152 work/rootfs/etc/modules.d/20-ps5-usb-net)" = 1
printf '%s\n' password > private/root-password.txt
chmod 600 private/root-password.txt
HASH=$(openssl passwd -6 -stdin < private/root-password.txt)
ROOTFS="$ROOT/work/rootfs" ROOT_HASH="$HASH" python3 - <<'PY'
import os
from pathlib import Path
p=Path(os.environ['ROOTFS'])/'etc/shadow'
lines=p.read_text().splitlines()
for i,line in enumerate(lines):
    if line.startswith('root:'):
        fields=line.split(':'); fields[1]=os.environ['ROOT_HASH']; lines[i]=':'.join(fields)
p.write_text('\n'.join(lines)+'\n');p.chmod(0o600)
PY
chroot work/rootfs /sbin/uci -q set luci.main.mediaurlbase=/luci-static/argon
chroot work/rootfs /sbin/uci commit luci
cmp files/etc/config/network work/rootfs/etc/config/network
test -x work/rootfs/bin/coremark
test -d work/rootfs/www/luci-static/argon
chroot work/rootfs /usr/bin/apk info -e luci-theme-argon coremark
# Retain the previous deliverables in the revision backup before replacing them.
rm -f output/ps5-openwrt-25.12.6-13xx-experimental.img output/ps5-openwrt-25.12.6-13xx-experimental.img.xz output/validation-vm.json output/image-before-test.sha256
chown -R ub:ub output
chown ub:ub private/root-password.txt
echo '=== EXTRA PACKAGES INTEGRATED ==='

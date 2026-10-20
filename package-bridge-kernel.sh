#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/ub/ps5-openwrt-13.00
test "$(cat logs/bridge-kernel.exit)" = 0
grep -Fx 'CONFIG_BRIDGE_VLAN_FILTERING=y' output/kernel.config
KVER=$(cat output/kernel.release)
test "$KVER" = 7.1.7-ps5-openwrt
mkdir -p "work/kernel-package/lib/modules/$KVER" work/kernel-package/usr/share/ps5-openwrt
find "work/kernel-stage/lib/modules/$KVER/kernel" -type f -name '*.ko' -print0 | while IFS= read -r -d '' module; do
    install -m 644 "$module" "work/kernel-package/lib/modules/$KVER/$(basename "$module")"
done
cp "work/kernel-stage/lib/modules/$KVER/modules.builtin" "work/kernel-stage/lib/modules/$KVER/modules.builtin.modinfo" "work/kernel-package/lib/modules/$KVER/"
cp output/kernel.config output/kernel.release work/kernel-package/usr/share/ps5-openwrt/
PROVIDES=$(python3 - <<'PY'
from pathlib import Path
lines=Path('work/revisions/pre-lan-ap-20261020/kernel-info/kernel-provides.txt').read_text().splitlines()
items=list(dict.fromkeys(x.strip() for x in lines if x.strip() and not x.endswith('provides:')))
assert all(' ' not in item and ':' not in item for item in items),items
assert any(x.startswith('kmod-') for x in items),items
print(' '.join(x.replace('7.1.7-r1001','7.1.7-r1003') for x in items)+' kmod-bridge=7.1.7-r1003')
PY
)
chown -R root:root work/kernel-package
work/openwrt-sdk/staging_dir/host/bin/apk mkpkg --files work/kernel-package \
    --info name:kernel --info version:7.1.7-r1003 --info arch:x86_64 \
    --info 'description:PS5 7.1.7 kernel with OpenWrt LAN bridge VLAN support and matching modules' \
    --info license:GPL-2.0-only --info depends:libc --info "provides:$PROVIDES" \
    --sign-key private/apk-signing.pem --output output/kernel-7.1.7-r1003.apk
# Refresh the storage-only initramfs with modules from the same kernel build.
cp "work/kernel-stage/lib/modules/$KVER/modules.builtin" "work/kernel-stage/lib/modules/$KVER/modules.builtin.modinfo" "work/initramfs/lib/modules/$KVER/"
INITRAMFS_TARGET="$PWD/work/initramfs"
modprobe -d "$PWD/work/kernel-stage" -S "$KVER" --show-depends uas | awk '$1 == "insmod" {print $2}' | while IFS= read -r source; do
    relative=${source#"$PWD/work/kernel-stage/"}
    test "$relative" != "$source"
    (cd work/kernel-stage && cp --parents "$relative" "$INITRAMFS_TARGET/")
done
depmod -b "$PWD/work/initramfs" "$KVER"
(cd work/initramfs && find . -print0 | cpio --null -o --format=newc --quiet | gzip -n -9) > output/initrd.img
echo 'Bridge-capable kernel package and matching initramfs prepared.'

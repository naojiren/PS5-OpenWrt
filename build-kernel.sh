#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p downloads work output logs
exec 9>work/kernel.lock
flock -n 9 || { echo 'Kernel build already running'; exit 1; }
trap 'rc=$?; echo "KERNEL_EXIT=$rc"; printf "%s\n" "$rc" > "$ROOT/logs/kernel.exit"' EXIT
VERSION=7.1.7
PATCH_SHA=56922cf9af91142cdcf7d54cbcfb3d46bdfb397a
fetch() {
    if ! test -s "$2"; then
        curl -fL --retry 4 --connect-timeout 20 "$1" -o "$2.part"
        mv "$2.part" "$2"
    fi
}
echo "=== Downloading Linux $VERSION and OpenWrt 25.12.6 ==="
fetch "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$VERSION.tar.xz" "downloads/linux-$VERSION.tar.xz"
fetch 'https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc' downloads/linux-sha256sums.asc
grep " linux-$VERSION.tar.xz\$" downloads/linux-sha256sums.asc > downloads/kernel.sha256
(cd downloads && sha256sum -c kernel.sha256)
BASE=https://downloads.openwrt.org/releases/25.12.6/targets/x86/64
fetch "$BASE/sha256sums" downloads/openwrt-sha256sums
fetch "$BASE/openwrt-25.12.6-x86-64-rootfs.tar.gz" downloads/openwrt-25.12.6-x86-64-rootfs.tar.gz
grep ' \*openwrt-25.12.6-x86-64-rootfs.tar.gz$' downloads/openwrt-sha256sums > downloads/rootfs.sha256
(cd downloads && sha256sum -c rootfs.sha256)
if test ! -d work/patches/.git; then
    git clone --depth 1 --branch kernel-7.1.7-56922cf https://github.com/ps5-linux/ps5-linux-patches.git work/patches
fi
test "$(git -C work/patches rev-parse HEAD)" = "$PATCH_SHA"
if test ! -f work/linux/.ps5-patched; then
    test ! -e work/linux || { echo 'Incomplete source tree needs inspection'; exit 1; }
    mkdir -p work/linux
    tar -xJf "downloads/linux-$VERSION.tar.xz" --strip-components=1 -C work/linux
    git -C work/linux apply --check "$ROOT/work/patches/linux.patch"
    git -C work/linux apply "$ROOT/work/patches/linux.patch"
    cp work/patches/.config work/linux/.config
    touch work/linux/.ps5-patched
fi
for local_patch in "$ROOT"/kernel-patches/*.patch; do
    test -f "$local_patch" || continue
    if ! git -C work/linux apply --reverse --check "$local_patch" 2>/dev/null; then
        git -C work/linux apply --check "$local_patch"
        git -C work/linux apply "$local_patch"
    fi
done
cd work/linux
echo '=== Configuring PS5 kernel, networking and validation drivers ==='
scripts/config --set-str LOCALVERSION '-ps5-openwrt' --disable LOCALVERSION_AUTO \
    --disable DEBUG_INFO --enable DEBUG_INFO_NONE --disable DEBUG_INFO_DWARF5 \
    --disable DEBUG_INFO_BTF --disable DEBUG_INFO_BTF_MODULES \
    --set-str SYSTEM_TRUSTED_KEYS '' --set-str SYSTEM_REVOCATION_KEYS '' \
    --disable MODULE_COMPRESS --enable MODULE_COMPRESS_NONE \
    --enable X86_PS5 --enable DEVTMPFS --enable DEVTMPFS_MOUNT \
    --enable VIRTIO_BLK --enable VIRTIO_NET --enable VIRTIO_CONSOLE \
    --enable NETFILTER --enable NF_CONNTRACK --enable NF_NAT --enable NF_TABLES \
    --enable NF_TABLES_INET --enable NFT_QUOTA --enable NFT_HASH \
    --enable NFT_SOCKET --enable NFT_TPROXY --enable NFT_FIB_INET \
    --enable NFT_FIB_IPV4 --enable NFT_FIB_IPV6 --enable NFT_REJECT_INET \
    --enable BRIDGE --enable BRIDGE_VLAN_FILTERING --enable VLAN_8021Q --enable TUN --enable VETH --enable WIREGUARD \
    --enable USB_RTL8152 --enable USB_NET_AX8817X --enable USB_NET_AX88179_178A \
    --enable NET_SCH_CAKE --enable NET_SCH_FQ_CODEL --enable NET_SCH_HTB \
    --enable NET_CLS_U32 --enable NET_CLS_FW --enable NET_ACT_MIRRED \
    --enable NF_CONNTRACK_PROCFS
# Keep routing functionality built in, independent of OpenWrt's stock kmods.
python3 - <<'PY'
import re
from pathlib import Path
p=Path('.config')
s=p.read_text()
s=re.sub(r'^(CONFIG_(?:NETFILTER\w*|NF_\w*|NFT_\w*|BRIDGE\w*|VLAN_8021Q\w*|PPP\w*|SLHC|CRYPTO_\w*))=m$', r'\1=y', s, flags=re.M)
p.write_text(s)
PY
make olddefconfig
cp .config "$ROOT/output/kernel.config"
echo '=== Compiling kernel and matching modules (3 jobs) ==='
nice -n 10 make -j3 bzImage modules
echo '=== Installing matching modules into staging tree ==='
mkdir -p "$ROOT/work/kernel-stage"
make modules_install INSTALL_MOD_PATH="$ROOT/work/kernel-stage" INSTALL_MOD_STRIP=1
KVER=$(make -s kernelrelease)
printf '%s\n' "$KVER" > "$ROOT/output/kernel.release"
cp arch/x86/boot/bzImage "$ROOT/output/bzImage"
cp System.map "$ROOT/output/System.map"
rm -f "$ROOT/work/kernel-stage/lib/modules/$KVER/build" "$ROOT/work/kernel-stage/lib/modules/$KVER/source"
echo "=== KERNEL COMPLETE: $KVER ==="

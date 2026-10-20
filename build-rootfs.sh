#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ROOTFS_ERROR_LINE=$LINENO" >&2' ERR
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" = 0 || { echo 'Root required for image ownership and chroot'; exit 1; }
test -s output/bzImage
test -s output/kernel.release
test "$(cat logs/kernel.exit)" = 0
KVER=$(cat output/kernel.release)
PKGVER=7.1.7-r1003
ALPINE=alpine@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0
mkdir -p private output logs
chmod 700 private
if ! test -s private/apk-signing.pem; then
    openssl genrsa -out private/apk-signing.pem 2048
fi
openssl rsa -in private/apk-signing.pem -pubout -out private/ps5-openwrt.rsa.pub
chmod 600 private/apk-signing.pem
if ! test -f work/.rootfs-packaged; then
# Stage the actual matching modules. OpenWrt's kmodloader scans a flat directory.
test ! -d work/kernel-package || { echo 'Kernel package already staged'; exit 1; }
mkdir -p "work/kernel-package/lib/modules/$KVER" work/kernel-package/usr/share/ps5-openwrt
find "work/kernel-stage/lib/modules/$KVER/kernel" -type f -name '*.ko' -print0 | while IFS= read -r -d '' module; do
    dest="work/kernel-package/lib/modules/$KVER/$(basename "$module")"
    test ! -e "$dest" || { echo "Duplicate module name: $module"; exit 1; }
    cp "$module" "$dest"
done
cp "work/kernel-stage/lib/modules/$KVER/modules.builtin" "work/kernel-package/lib/modules/$KVER/"
cp "work/kernel-stage/lib/modules/$KVER/modules.builtin.modinfo" "work/kernel-package/lib/modules/$KVER/"
cp output/kernel.config output/kernel.release work/kernel-package/usr/share/ps5-openwrt/
PROVIDES='kernel-any'
while IFS= read -r name; do
    test "$name" = kmod-button-hotplug && continue
    PROVIDES="$PROVIDES $name=$PKGVER"
done < <(grep '^kmod-' work/rootfs/etc/apk/world)
for pair in 'kmod-tun:TUN' 'kmod-veth:VETH' 'kmod-wireguard:WIREGUARD' 'kmod-nft-tproxy:NFT_TPROXY' 'kmod-nft-socket:NFT_SOCKET' 'kmod-sched-cake:NET_SCH_CAKE'; do
    capability=${pair%%:*}
    symbol=${pair#*:}
    grep -Eq "^CONFIG_$symbol=[ym]$" output/kernel.config || { echo "Missing kernel feature: $symbol"; exit 1; }
    PROVIDES="$PROVIDES $capability=$PKGVER"
done
chown -R root:root work/kernel-package
docker run --rm -v "$ROOT:/build" "$ALPINE" \
    apk mkpkg --compat 3.0.5 --files /build/work/kernel-package \
    --info name:kernel --info "version:$PKGVER" --info arch:x86_64 \
    --info 'description:PS5 7.1.7 kernel, matching modules and built-in router support' \
    --info 'license:GPL-2.0-only' --info depends:libc --info "provides:$PROVIDES" \
    --sign-key /build/private/apk-signing.pem --output "/build/output/kernel-$PKGVER.apk"
install -m 644 private/ps5-openwrt.rsa.pub work/rootfs/etc/apk/keys/
cp "output/kernel-$PKGVER.apk" work/rootfs/tmp/
sed -i '/^kernel[=~<>]/d; /^kmod-/d' work/rootfs/etc/apk/world
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add "/tmp/kernel-$PKGVER.apk"
sed -i '\|/kmods/|d' work/rootfs/etc/apk/repositories.d/distfeeds.list
chroot work/rootfs /usr/bin/apk update
chroot work/rootfs /usr/bin/apk --no-scripts add luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn ip-full wireguard-tools luci-proto-wireguard
test -x work/rootfs/usr/libexec/ip-full
ln -sf /usr/libexec/ip-full work/rootfs/sbin/ip
chroot work/rootfs /usr/bin/apk --no-scripts del luci-app-attendedsysupgrade attendedsysupgrade-common owut
cp -a files/. work/rootfs/
chmod 755 work/rootfs/etc/uci-defaults/99-ps5 work/rootfs/etc/hotplug.d/net/95-ps5-redirects
chmod 755 work/rootfs/etc/hotplug.d/iface/95-ps5-redirects
rm -f work/rootfs/etc/rc.d/*odhcpd
printf '%s\n' 'password' > private/root-password.txt
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
p.write_text('\n'.join(lines)+'\n')
p.chmod(0o600)
PY
rm -f work/rootfs/etc/resolv.conf
ln -s /tmp/resolv.conf work/rootfs/etc/resolv.conf
rm -f work/rootfs/tmp/kernel-*.apk
mkdir -p work/rootfs/boot/efi
cat > work/rootfs/etc/banner <<'EOF'
 -----------------------------------------------------
 PS5 OpenWrt 25.12.6 experimental / PS5 kernel 7.1.7
 External drive only. PS5 hardware validation pending.
 Generic OpenWrt kernel upgrades are not supported.
 -----------------------------------------------------
EOF
# Initial console and module loading work without a desktop environment.
cat > work/rootfs/etc/inittab <<'EOF'
::sysinit:/etc/init.d/rcS S boot
::shutdown:/etc/init.d/rcS K shutdown
ttyS0::askfirst:/usr/libexec/login.sh
hvc0::askfirst:/usr/libexec/login.sh
tty1::askfirst:/usr/libexec/login.sh
EOF
touch work/.rootfs-packaged
fi
echo '=== Adding AMD firmware for the PS5 display driver ==='
mkdir -p work/rootfs/lib/firmware/amdgpu
FWCOUNT=0
for source in /usr/lib/firmware/amdgpu/*.bin*; do
    test -e "$source" || continue
    filename=$(basename "$source")
    case "$filename" in
        *.zst) zstd -dcf "$source" > "work/rootfs/lib/firmware/amdgpu/${filename%.zst}" ;;
        *.xz) xz -dcf "$source" > "work/rootfs/lib/firmware/amdgpu/${filename%.xz}" ;;
        *) cp -L "$source" work/rootfs/lib/firmware/amdgpu/ ;;
    esac
    FWCOUNT=$((FWCOUNT+1))
done
test "$FWCOUNT" -gt 0 || { echo 'PS5 display firmware unavailable; inspect required files'; exit 1; }
test -f /usr/share/doc/linux-firmware-amd-graphics/copyright
cp /usr/share/doc/linux-firmware-amd-graphics/copyright work/rootfs/lib/firmware/LICENSE.amdgpu-ubuntu
dpkg-query -W linux-firmware-amd-graphics > output/firmware-source.txt
(cd work/rootfs/lib/firmware && sha256sum amdgpu/*.bin) > output/firmware-sha256sums.txt
# Build a small storage-only initramfs. PS5 USB/storage/ext4 are built in.
test ! -d work/initramfs || { echo 'Initramfs already staged'; exit 1; }
mkdir -p work/initramfs/{bin,sbin,dev,proc,sys,newroot}
mknod -m 600 work/initramfs/dev/console c 5 1
mknod -m 666 work/initramfs/dev/null c 1 3
cp /usr/bin/busybox work/initramfs/bin/busybox
file work/initramfs/bin/busybox | grep 'statically linked' >/dev/null
chroot work/initramfs /bin/busybox --install -s /bin
install -m 755 initramfs-init work/initramfs/init
chroot work/initramfs /bin/busybox --list | grep -x findfs >/dev/null
mkdir -p "work/initramfs/lib/modules/$KVER"
cp "work/kernel-stage/lib/modules/$KVER/modules.builtin" "work/initramfs/lib/modules/$KVER/"
cp "work/kernel-stage/lib/modules/$KVER/modules.builtin.modinfo" "work/initramfs/lib/modules/$KVER/"
modprobe -d "$ROOT/work/kernel-stage" -S "$KVER" --show-depends uas | awk '$1 == "insmod" {print $2}' | while IFS= read -r source; do
    relative=${source#"$ROOT/work/kernel-stage/"}
    test "$relative" != "$source"
    (cd work/kernel-stage && cp --parents "$relative" "$ROOT/work/initramfs/")
done
depmod -b "$ROOT/work/initramfs" "$KVER"
(cd work/initramfs && find . -print0 | cpio --null -o --format=newc --quiet | gzip -n -9) > output/initrd.img
printf '%s\n' 'root=LABEL=ps5-openwrt rw rootwait console=ttyTitania0 console=tty0 video=DP-1:1920x1080@60 mitigations=off idle=halt preempt=full' > output/cmdline.txt
printf '%s\n' '0x20000000' > output/vram.txt
chown ub:ub output/* private private/apk-signing.pem private/root-password.txt private/ps5-openwrt.rsa.pub
echo '=== ROOTFS COMPLETE ==='

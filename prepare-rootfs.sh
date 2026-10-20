set -Eeuo pipefail
export LC_ALL=C
ROOT=/home/ub/ps5-openwrt-13.00
cd "$ROOT"
mkdir -p downloads work output logs
if ! test -s downloads/openwrt-25.12.6-x86-64-rootfs.tar.gz; then
    curl -fL --retry 3 https://downloads.openwrt.org/releases/25.12.6/targets/x86/64/openwrt-25.12.6-x86-64-rootfs.tar.gz -o downloads/openwrt-25.12.6-x86-64-rootfs.tar.gz
fi
echo '55e52bb34de582a1ebe56bd50f94ff54ac7c77f5bca9cae807656d1930456da4  downloads/openwrt-25.12.6-x86-64-rootfs.tar.gz' | sha256sum -c -
test ! -d work/rootfs || { echo 'Rootfs exists; inspect before replacing'; exit 1; }
mkdir -p work/rootfs
tar -xzf downloads/openwrt-25.12.6-x86-64-rootfs.tar.gz -C work/rootfs
rm -f work/rootfs/etc/resolv.conf
cp -L /etc/resolv.conf work/rootfs/etc/resolv.conf
for entry in 'null 1 3' 'zero 1 5' 'random 1 8' 'urandom 1 9'; do
    set -- $entry
    test -e "work/rootfs/dev/$1" || mknod -m 666 "work/rootfs/dev/$1" c "$2" "$3"
done
chroot work/rootfs /usr/bin/apk --version

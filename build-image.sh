#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" = 0
test -s output/bzImage && test -s output/initrd.img
test -f work/rootfs/etc/shadow
mkdir -p output logs
IMG=output/ps5-openwrt-25.12.6-13xx-experimental.img
test ! -e "$IMG" || { echo 'Image already exists; inspect before overwriting'; exit 1; }
printf '=== Creating external drive image (files only) ===\n'
truncate -s 4096M "$IMG"
parted -s "$IMG" mklabel gpt
parted -s "$IMG" mkpart primary ext4 257MiB 4095MiB
parted -s "$IMG" mkpart primary fat32 1MiB 257MiB
parted -s "$IMG" set 2 esp on
truncate -s 3838M work/root.ext4
mkfs.ext4 -F -L ps5-openwrt -m 0 -d work/rootfs work/root.ext4
e2fsck -fn work/root.ext4
truncate -s 256M work/boot.fat
mkfs.vfat -F 32 -n boot work/boot.fat
mcopy -i work/boot.fat output/bzImage output/initrd.img output/cmdline.txt output/vram.txt ::/
test ! -f output/ps5-linux-loader-13xx.elf || mcopy -i work/boot.fat output/ps5-linux-loader-13xx.elf ::/
fsck.fat -n work/boot.fat
dd if=work/root.ext4 of="$IMG" bs=1M seek=257 conv=notrunc,sparse status=progress
dd if=work/boot.fat of="$IMG" bs=1M seek=1 conv=notrunc,sparse status=none
parted -sm "$IMG" unit s print > output/partitions.txt
chroot work/rootfs /usr/bin/apk list --installed > output/packages.txt
ROOT="$ROOT" python3 - <<'PY'
from pathlib import Path
import hashlib,json,os,datetime,subprocess
p=Path(os.environ['ROOT'])
def sha(name):
    h=hashlib.sha256()
    with (p/name).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
data={
 'name':'PS5 OpenWrt experimental', 'revision':'lan-ap-mts-openclash-mihomo-20261020', 'openwrt':'25.12.6',
 'kernel_release':(p/'output/kernel.release').read_text().strip(),
 'ps5_patches_commit':'56922cf9af91142cdcf7d54cbcfb3d46bdfb397a',
 'kernel_package':'7.1.7-r1003',
 'kernel_local_patches':{f.relative_to(p).as_posix():sha(f.relative_to(p).as_posix()) for f in (p/'kernel-patches').glob('*.patch')},
 'ethernet_filter_backport':json.loads((p/'kernel-patches/mts-rx-filter-provenance.json').read_text()),
 'ps5_loader_commit':'691e50f35953674cdeebe1306a01c7b7442cdc12',
 'ps5_loader_local_patches':{'loader-patches/13.00-wifi-offset.patch':sha('loader-patches/13.00-wifi-offset.patch')},
 'builder_image':'alpine@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'intended_hardware':'PS5 Phat/Slim; user console CFI-2200 B01, assuming supported 13.00 jailbreak',
 'ps5_hardware_tested':False, 'rootfs_source':'Official OpenWrt binary userspace; PS5 kernel built from patched source',
 'network':{'lan':'DHCP client on br-lan','bridge':'br-lan','bridge_ports':['preferred PS5 wired Ethernet','PS5 IW620 Wi-Fi AP'],'upstream_dhcp_for_clients':True,'bridge_mac':'Preferred wired Ethernet MAC','rescue':'172.31.55.1/24','dhcp_server':False,'ipv4_forwarding':True,'lan_masquerading':True},
 'wireless_defaults':{'enabled':True,'mode':'ap','ssid':'PS5-OpenWrt','encryption':'none','country':'CN','band':'5g','channel':36,'htmode':'HE80','network':'lan'},
 'default_login':{'username':'root','password':'password','ssh_port':22},
 'features':{'luci':True,'default_theme':'argon','coremark':{'enabled':True,'multithreading':True,'default_threads':16},'rtl8156b':{'driver':'r8152','matching_ps5_kernel':True,'firmware':'rtl_nic/rtl8156b-2.fw','usb_adapter_hardware_tested':False},'iw620':{'driver_modules':['mlan','moal'],'matching_ps5_kernel':True,'firmware':'Exported by patched PS5 Linux loader with header/data CRC validation; refreshed from boot partition when changed','signed_regulatory_database':True,'wireless_hardware_tested':False}},
 'input_sha256':{n:sha(n) for n in ['downloads/linux-7.1.7.tar.xz','downloads/openwrt-25.12.6-x86-64-rootfs.tar.gz','output/kernel.config','downloads/ps5-payload-sdk.zip']},
 'limitations':['External storage only','No generic OpenWrt sysupgrade or stock kernel modules','Onboard Wi-Fi driver compiled; association and throughput require real PS5 verification','PS5 cold boot requires jailbreak and Linux loader again']
}
if (p/'output/extra-packages/build-provenance.json').is_file():
 data['extra_packages']=json.loads((p/'output/extra-packages/build-provenance.json').read_text())
if (p/'output/wifi/build-provenance.json').is_file():
 data['wifi_build']=json.loads((p/'output/wifi/build-provenance.json').read_text())
if (p/'output/fan/build-provenance.json').is_file():
 data['fan_control']=json.loads((p/'output/fan/build-provenance.json').read_text())
if (p/'output/openclash/build-provenance.json').is_file():
 data['features']['openclash']=json.loads((p/'output/openclash/build-provenance.json').read_text())
if (p/'ps5-bridge-hardware-validation.json').is_file():
 data['component_hardware_validation']=json.loads((p/'ps5-bridge-hardware-validation.json').read_text())
(p/'output/build-manifest.json').write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
PY
chown ub:ub output/*
echo '=== IMAGE COMPLETE ==='

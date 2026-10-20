#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" = 0
test "$(cat logs/wifi.exit)" = 0
test "$(cat logs/integrate.exit)" = 0
mkdir -p work/wifi-downloads work/rootfs/tmp/wifi-offline/{base,target}
# Resolve URLs using the existing signed index, then download on the build host.
# --simulate is required: --url by itself still fetches files inside the chroot.
chroot work/rootfs /usr/bin/apk fetch --cache-max-age 1000000 --simulate --url --recursive iw iwinfo wpad-basic-mbedtls wireless-regdb block-mount wifi-scripts > work/wifi-package-urls.txt
python3 - <<'PY'
import concurrent.futures,hashlib,json,urllib.request
from pathlib import Path
p=Path('.')
urls=[u.strip() for u in (p/'work/wifi-package-urls.txt').read_text().splitlines() if u.strip()]
def download(url):
    if not url.startswith('https://downloads.openwrt.org/releases/25.12.6/'):raise RuntimeError('Unexpected package origin')
    name=url.rsplit('/',1)[1]
    if name.startswith(('kernel-','kmod-')):raise RuntimeError('Stock kernel modules must not be installed')
    target=p/'work/wifi-downloads'/name
    if not target.is_file():
        with urllib.request.urlopen(url,timeout=45) as response: data=response.read()
        partial=target.with_suffix('.apk.part');partial.write_bytes(data);partial.replace(target)
    return {'url':url,'name':name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:records=list(pool.map(download,urls))
import shutil
for record in records:
    repo='target' if '/targets/x86/64/packages/' in record['url'] else 'base'
    shutil.copyfile(p/'work/wifi-downloads'/record['name'],p/'work/rootfs/tmp/wifi-offline'/repo/record['name'])
index_urls={'target':'https://downloads.openwrt.org/releases/25.12.6/targets/x86/64/packages/packages.adb','base':'https://downloads.openwrt.org/releases/25.12.6/packages/x86_64/base/packages.adb'}
indexes={}
for repo,url in index_urls.items():
    with urllib.request.urlopen(url,timeout=45) as response:data=response.read()
    (p/'work/rootfs/tmp/wifi-offline'/repo/'packages.adb').write_bytes(data)
    indexes[repo]={'url':url,'sha256':hashlib.sha256(data).hexdigest()}
(p/'output/wifi/signed-repository-indexes.json').write_text(json.dumps(indexes,indent=2)+'\n')
(p/'output/wifi/userspace-packages.json').write_text(json.dumps(records,indent=2)+'\n')
print('Downloaded official wireless userspace packages and signed indexes:',len(records),flush=True)
PY
for repo in base target; do
    chroot work/rootfs /usr/bin/apk verify "/tmp/wifi-offline/$repo/packages.adb"
done
# Official individual APKs are unsigned. APK verifies their hashes through the
# signed index when installing from the local mirror, preserving normal trust.
chroot work/rootfs /usr/bin/apk --no-network --no-scripts \
    -X file:///tmp/wifi-offline/base/packages.adb \
    -X file:///tmp/wifi-offline/target/packages.adb \
    add iw iwinfo wpad-basic-mbedtls wireless-regdb block-mount wifi-scripts
rm -f work/rootfs/tmp/wifi-packages/*.apk work/rootfs/tmp/coremark-sign-probe.apk work/rootfs/tmp/block-mount-*.apk work/rootfs/tmp/iw-*.apk work/rootfs/tmp/wifi-scripts-*.apk
cp -a files/. work/rootfs/
chmod 755 work/rootfs/etc/uci-defaults/99-ps5 work/rootfs/etc/hotplug.d/net/95-ps5-redirects work/rootfs/etc/hotplug.d/iface/95-ps5-redirects
mkdir -p work/wifi-package/etc/init.d work/wifi-package/etc/modules-boot.d work/wifi-package/usr/share/ps5-openwrt
install -m 755 files/etc/init.d/ps5-wifi work/wifi-package/etc/init.d/ps5-wifi
install -m 644 files/etc/modules-boot.d/12-ps5-boot-fat work/wifi-package/etc/modules-boot.d/12-ps5-boot-fat
mkdir -p work/wifi-package/etc/config
install -m 644 files/etc/config/wireless work/wifi-package/etc/config/wireless
python3 - <<'PY'
import json
from pathlib import Path
p=Path('output/wifi/build-provenance.json')
d=json.loads(p.read_text())
d['revision']='7.1.7-r5'
d['startup_fixes']=['Detect NXP mwiphy0 radio name','Set configured regulatory domain before IW620 probe','Allow up to 30 seconds for radio initialization']
d['wireless_defaults']={'enabled':True,'mode':'ap','ssid':'PS5-OpenWrt','country':'CN','band':'5g','channel':36,'encryption':'none','network':'lan'}
p.write_text(json.dumps(d,indent=2)+'\n')
PY
cp output/wifi/build-provenance.json work/wifi-package/usr/share/ps5-openwrt/wifi-build-provenance.json
openssl cms -verify -binary -inform DER -in /usr/lib/firmware/regulatory.db.p7s -content /usr/lib/firmware/regulatory.db -noverify -out /dev/null
mkdir -p work/wifi-package/usr/share/ps5-openwrt/regdb
install -m 644 /usr/lib/firmware/regulatory.db /usr/lib/firmware/regulatory.db.p7s work/wifi-package/usr/share/ps5-openwrt/regdb/
install -m 644 /usr/share/doc/wireless-regdb/copyright work/wifi-package/usr/share/ps5-openwrt/regdb/COPYING
# Let the Wi-Fi package own its service and autoload file.
if ! chroot work/rootfs /usr/bin/apk info -e ps5-iw620 >/dev/null; then
    rm -f work/rootfs/etc/init.d/ps5-wifi work/rootfs/etc/modules-boot.d/12-ps5-boot-fat
fi
chown -R root:root work/wifi-package
work/openwrt-sdk/staging_dir/host/bin/apk mkpkg --files work/wifi-package \
    --info name:ps5-iw620 --info version:7.1.7-r5 --info arch:x86_64 \
    --info 'description:PS5 IW620 Wi-Fi driver matched to the PS5 OpenWrt kernel' \
    --info 'license:GPL-2.0-only AND ISC' \
    --info 'depends:kernel=7.1.7-r1003 block-mount iw iwinfo wpad-basic-mbedtls wifi-scripts wireless-regdb' \
    --info 'provides:kmod-cfg80211=7.1.7-r1003 kmod-mac80211=7.1.7-r1003' \
    --sign-key private/apk-signing.pem --output output/wifi/ps5-iw620-7.1.7-r5.apk
cp output/wifi/ps5-iw620-7.1.7-r5.apk work/rootfs/tmp/
chroot work/rootfs /usr/bin/apk verify /tmp/ps5-iw620-7.1.7-r5.apk
chroot work/rootfs /usr/bin/apk --no-network --no-scripts add /tmp/ps5-iw620-7.1.7-r5.apk
rm -f work/rootfs/tmp/ps5-iw620-7.1.7-r5.apk
chmod 755 work/rootfs/etc/init.d/ps5-wifi
mkdir -p work/rootfs/tmp/lock
for service in ps5-wifi fstab wpad; do chroot work/rootfs "/etc/init.d/$service" enable; done
find work/rootfs/tmp/wifi-offline -type f -delete
cmp files/etc/config/network work/rootfs/etc/config/network
chroot work/rootfs /usr/bin/apk info -e ps5-iw620 wifi-scripts iw wpad-basic-mbedtls wireless-regdb
chown -R ub:ub output
echo '=== WIFI INTEGRATION COMPLETE ==='

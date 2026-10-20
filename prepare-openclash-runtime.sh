#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/home/ub/ps5-openwrt-13.00
cd "$ROOT"
test "$(id -u)" = 0
runtime=(kernel ps5-openclash-support dnsmasq-full bash curl ca-bundle ip-full ruby ruby-yaml unzip luci-compat)
mkdir -p work/openclash-downloads work/rootfs/tmp/openclash-offline/ps5 work/openclash-support-package/etc/modules.d
grep -Fx 'CONFIG_NF_CT_NETLINK=y' output/kernel.config
grep -Fx 'CONFIG_INET_DIAG=m' output/kernel.config
test -s work/rootfs/lib/modules/7.1.7-ps5-openwrt/inet_diag.ko
printf '%s\n' inet_diag tcp_diag udp_diag >work/openclash-support-package/etc/modules.d/25-ps5-openclash
work/openwrt-sdk/staging_dir/host/bin/apk mkpkg --files work/openclash-support-package \
    --info name:ps5-openclash-support --info version:1.0.0-r1 --info arch:x86_64 \
    --info 'description:OpenClash netlink capability metadata and diagnostic module autoload for PS5' \
    --info license:GPL-2.0-only --info 'depends:kernel=7.1.7-r1003' \
    --info 'provides:kmod-nf-conntrack-netlink=7.1.7-r1003 kmod-inet-diag=7.1.7-r1003' \
    --sign-key private/apk-signing.pem --output output/openclash/ps5-openclash-support-1.0.0-r1.apk
cp output/kernel-7.1.7-r1003.apk output/openclash/ps5-openclash-support-1.0.0-r1.apk work/rootfs/tmp/openclash-offline/ps5/
chroot work/rootfs /usr/bin/apk verify /tmp/openclash-offline/ps5/kernel-7.1.7-r1003.apk /tmp/openclash-offline/ps5/ps5-openclash-support-1.0.0-r1.apk
# The SDK indexer lacks the image's trust store; inputs are verified above and
# the generated index is signed and subsequently verified inside the image.
work/openwrt-sdk/staging_dir/host/bin/apk --allow-untrusted mkndx --sign-key private/apk-signing.pem \
    --output work/rootfs/tmp/openclash-offline/ps5/packages.adb \
    work/rootfs/tmp/openclash-offline/ps5/*.apk
chroot work/rootfs /usr/bin/apk fetch -X file:///tmp/openclash-offline/ps5/packages.adb \
    --cache-max-age 1000000 --simulate --url --recursive "${runtime[@]}" >work/openclash-package-urls.txt
test -s work/openclash-package-urls.txt
python3 - <<'PY'
import concurrent.futures,hashlib,json,urllib.request,shutil,gzip,subprocess,time
from pathlib import Path
p=Path('.')
def fetch(url,dest):
    for attempt in range(4):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'PS5-OpenWrt-builder'})
            with urllib.request.urlopen(req,timeout=90) as response: data=response.read()
            target=dest.with_name(dest.name+'.part');target.write_bytes(data);target.replace(dest)
            return data
        except Exception:
            if attempt==3:raise
            time.sleep(3)
def download(url):
    assert url.startswith('https://downloads.openwrt.org/releases/25.12.6/'),url
    name=url.rsplit('/',1)[1]
    assert not name.startswith(('kernel-','kmod-')),name
    dest=p/'work/openclash-downloads'/name
    if not dest.is_file():fetch(url,dest)
    return {'url':url,'name':name,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
urls=sorted(set(u.strip() for u in Path('work/openclash-package-urls.txt').read_text().splitlines() if u.strip() and not u.startswith('file:///tmp/openclash-offline/ps5/')))
assert urls,'No dependency URLs resolved'
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: records=list(pool.map(download,urls))
indexes={}
for rec in records:
    repo=rec['url'].rsplit('/',1)[0]
    label='target' if '/targets/' in repo else repo.rsplit('/',1)[1]
    directory=p/'work/rootfs/tmp/openclash-offline'/label;directory.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(p/'work/openclash-downloads'/rec['name'],directory/rec['name'])
    if label not in indexes:
        url=repo+'/packages.adb';data=fetch(url,directory/'packages.adb')
        indexes[label]={'url':url,'sha256':hashlib.sha256(data).hexdigest()}
Path('output/openclash/userspace-packages.json').write_text(json.dumps(records,indent=2)+'\n')
Path('output/openclash/signed-repository-indexes.json').write_text(json.dumps(indexes,indent=2)+'\n')
release=json.loads(Path('work/openclash-source-metadata/mihomo-release.json').read_text())
assert release['tag_name']=='v1.19.32'
name='mihomo-linux-amd64-compatible-v1.19.32.gz'
asset=next(a for a in release['assets'] if a['name']==name)
dest=Path('downloads')/name
data=dest.read_bytes() if dest.is_file() else fetch(asset['browser_download_url'],dest)
digest=hashlib.sha256(data).hexdigest()
assert asset['digest']=='sha256:'+digest,(asset['digest'],digest)
package=Path('work/mihomo-package')
binary=package/'etc/openclash/core/clash_meta';binary.parent.mkdir(parents=True,exist_ok=True)
binary.write_bytes(gzip.decompress(data));binary.chmod(0o755)
license=package/'usr/share/licenses/mihomo/LICENSE';license.parent.mkdir(parents=True,exist_ok=True)
fetch('https://raw.githubusercontent.com/MetaCubeX/mihomo/v1.19.32/LICENSE',license)
version=subprocess.check_output([str(binary.resolve()),'-v'],text=True).strip()
print('Mihomo downloaded and GitHub release digest verified:',version,flush=True)
provenance={'openclash_version':'0.48.002','openclash_commit':'e553e82e01c697aefbe1555261a503f425e00ccd',
 'openclash_source':'https://github.com/vernesong/OpenClash/tree/v0.48.002','openclash_build':'OpenWrt 25.12.6 SDK from source',
 'mihomo_version':'1.19.32','mihomo_asset':name,'mihomo_url':asset['browser_download_url'],
 'mihomo_release_digest':asset['digest'],'mihomo_compressed_sha256':digest,
 'mihomo_binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'mihomo_binary_version':version,
 'mihomo_build':'Official upstream prebuilt linux amd64 compatible static binary',
 'core_path':'/etc/openclash/core/clash_meta','default_core_type':'Meta','default_enabled':False,
 'requires_user_subscription':True,'kernel_package':'7.1.7-r1003'}
Path('output/openclash/build-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
print('Prepared offline userspace packages:',len(records),'signed repositories:',list(indexes),flush=True)
PY
for repo in work/rootfs/tmp/openclash-offline/*; do
    chroot work/rootfs /usr/bin/apk verify "/tmp/openclash-offline/$(basename "$repo")/packages.adb"
done
echo '=== GUI CORE ARCHITECTURE CHOICES ==='
sed -n '1515,1620p' work/openclash-source/luci-app-openclash/luasrc/model/cbi/openclash/settings.lua

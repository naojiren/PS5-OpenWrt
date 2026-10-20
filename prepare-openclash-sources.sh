#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/ub/ps5-openwrt-13.00
test "$(id -u)" != 0
mkdir -p downloads work/openclash-source-metadata output/openclash
python3 - <<'PY'
import json,urllib.request,time
from pathlib import Path
root=Path('work/openclash-source-metadata')
for name,repo,tag in [('openclash','vernesong/OpenClash','v0.48.002'),('mihomo','MetaCubeX/mihomo','v1.19.32')]:
    url='https://api.github.com/repos/'+repo+'/releases/tags/'+tag
    for attempt in range(4):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'PS5-OpenWrt-builder','Accept':'application/vnd.github+json'})
            with urllib.request.urlopen(req,timeout=45) as response:data=json.load(response)
            break
        except Exception:
            if attempt==3:raise
            time.sleep(3)
    assert data['tag_name']==tag
    (root/(name+'-release.json')).write_text(json.dumps(data,indent=2)+'\n')
    print(name, data['tag_name'],data['published_at'],flush=True)
    for a in data['assets']:
        if name=='openclash' or ('linux-amd64' in a['name'] and not any(x in a['name'] for x in ['go1','rpm','deb'])):
            print(a['name'],a['size'],a.get('digest'),flush=True)
openclash=json.loads((root/'openclash-release.json').read_text())
(root/'openclash-tag').write_text(openclash['tag_name'])
PY
tag=$(cat work/openclash-source-metadata/openclash-tag)
destination=work/openclash-source
if ! test -d "$destination/.git"; then
    git clone --depth 1 --branch "$tag" https://github.com/vernesong/OpenClash.git "$destination"
fi
test "$(git -C "$destination" describe --tags --exact-match)" = "$tag"
git -C "$destination" rev-parse HEAD
cat "$destination/luci-app-openclash/Makefile"
echo '=== CORE PATH AND DEFAULT OPTIONS ==='
grep -nE 'clash_meta|core_type|core_version|enable |en_mode|china_ip_route|dns_hijack' "$destination/luci-app-openclash/root/etc/config/openclash" | head -35

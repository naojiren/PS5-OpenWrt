#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
exec 9>work/wifi.lock
flock -n 9 || exit 90
trap 'rc=$?; echo "$rc" > "$ROOT/logs/wifi.exit"' EXIT
KVER=$(cat output/kernel.release)
test "$KVER" = 7.1.7-ps5-openwrt
PS5_COMMIT=4aff9085530a3cdf7d5fbb124c006cc299ac3605
if ! test -d work/ps5-linux-mwifiex/.git; then
    git clone https://github.com/ps5-linux/ps5-linux-mwifiex.git work/ps5-linux-mwifiex
    git -C work/ps5-linux-mwifiex checkout "$PS5_COMMIT"
fi
test "$(git -C work/ps5-linux-mwifiex rev-parse HEAD)" = "$PS5_COMMIT"
if ! test -d work/nxp-mwifiex/.git; then
    git clone --depth 1 --branch lf-6.18.2_1.0.0 https://github.com/nxp-imx/mwifiex.git work/nxp-mwifiex
fi
if ! test -f work/nxp-mwifiex/.ps5-patches-applied; then
    for patch in ps5-iw620.patch ps5-iw620-cmd-timeout-recover.patch ps5-iw620-kernel71-compat.patch ps5-iw620-rtnl-bounded-wait.patch; do
        git -C work/nxp-mwifiex apply --check "$ROOT/work/ps5-linux-mwifiex/$patch"
        git -C work/nxp-mwifiex apply "$ROOT/work/ps5-linux-mwifiex/$patch"
    done
    touch work/nxp-mwifiex/.ps5-patches-applied
fi
nice -n 10 make -C work/nxp-mwifiex CONFIG_OBJTOOL= KERNELDIR="$ROOT/work/linux" ARCH=x86 -j3
mkdir -p "work/wifi-package/lib/modules/$KVER" output/wifi
for name in mlan moal; do
    test "$(modinfo -F vermagic "work/nxp-mwifiex/$name.ko" | cut -d' ' -f1)" = "$KVER"
    install -m 644 "work/nxp-mwifiex/$name.ko" "work/wifi-package/lib/modules/$KVER/$name.ko"
    strip --strip-debug "work/wifi-package/lib/modules/$KVER/$name.ko"
    modinfo "work/wifi-package/lib/modules/$KVER/$name.ko" > "output/wifi/$name.modinfo.txt"
done
ROOT="$ROOT" python3 - <<'PY'
import os,json,subprocess
from pathlib import Path
p=Path(os.environ['ROOT'])
def rev(name):return subprocess.check_output(['git','-C',str(p/'work'/name),'rev-parse','HEAD'],text=True).strip()
data={'kernel':'7.1.7-ps5-openwrt','ps5_mwifiex_commit':rev('ps5-linux-mwifiex'),'nxp_mwifiex_commit':rev('nxp-mwifiex'),'nxp_ref':'lf-6.18.2_1.0.0','patches':['ps5-iw620.patch','ps5-iw620-cmd-timeout-recover.patch','ps5-iw620-kernel71-compat.patch','ps5-iw620-rtnl-bounded-wait.patch'],'firmware_source':'Extracted on the users PS5 by the Linux loader into boot partition lib/nxp/pcieuartiw620_combo_v1.bin','ps5_wifi_hardware_tested':False}
(p/'output/wifi/build-provenance.json').write_text(json.dumps(data,indent=2)+'\n')
PY
echo '=== WIFI MODULES COMPILED ==='

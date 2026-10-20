#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" != 0
exec 9>work/fan-build.lock
flock -n 9 || exit 90
trap 'rc=$?; echo "$rc" > "$ROOT/logs/fan-build.exit"' EXIT
TOOLS_SHA=f1fa98a931ca30783b2a91d999cbcba87121ee61
test "$(git -c safe.directory="$ROOT/work/ps5-linux-tools" -C work/ps5-linux-tools rev-parse HEAD)" = "$TOOLS_SHA"
SDK="$ROOT/work/openwrt-sdk"
mkdir -p "$SDK/package/luci-app-ps5-fan/src"
cp -a fan-plugin/. "$SDK/package/luci-app-ps5-fan/"
cp work/ps5-linux-tools/ps5_control.c "$SDK/package/luci-app-ps5-fan/src/"
cd "$SDK"
printf '\nCONFIG_PACKAGE_luci-app-ps5-fan=m\n' >> .config
make defconfig
nice -n 10 make -j3 package/luci-app-ps5-fan/compile V=s
mkdir -p "$ROOT/output/fan"
find bin/packages -type f -name 'luci-app-ps5-fan-*.apk' -exec cp -t "$ROOT/output/fan/" {} +
test -s "$ROOT/output/fan/luci-app-ps5-fan-1.0.0-r1.apk"
ROOT="$ROOT" TOOLS_SHA="$TOOLS_SHA" python3 - <<'PY'
import os,json
from pathlib import Path
p=Path(os.environ['ROOT'])
data={'ps5_linux_tools_commit':os.environ['TOOLS_SHA'],'sdk':'OpenWrt 25.12.6 x86_64 GCC 14.3.0 musl','default_boot_mode':'auto','default_target_celsius':80,'manual_modes':['maximum'],'arbitrary_percentage_or_rpm':False,'temperature_target_range_celsius':[40,80],'hardware_tested':False}
(p/'output/fan/build-provenance.json').write_text(json.dumps(data,indent=2)+'\n')
PY
echo '=== FAN PLUGIN COMPILED ==='

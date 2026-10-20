#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
test "$(id -u)" != 0 || { echo 'Compile SDK as ub, not root'; exit 1; }
mkdir -p downloads work logs output
exec 9>work/extra-packages.lock
flock -n 9 || { echo 'Extra package build already running'; exit 1; }
trap 'rc=$?; printf "%s\n" "$rc" > "$ROOT/logs/extra-packages.exit"' EXIT
SDK_NAME=openwrt-sdk-25.12.6-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst
SDK_SHA=1864152619092e781fa36a401960c8e9ae42d6a364c44ee5f0b197ca5f3c0fcc
if ! test -s "downloads/$SDK_NAME"; then
    curl -fL --retry 4 --connect-timeout 20 "https://downloads.openwrt.org/releases/25.12.6/targets/x86/64/$SDK_NAME" -o "downloads/$SDK_NAME.part"
    mv "downloads/$SDK_NAME.part" "downloads/$SDK_NAME"
fi
printf '%s  %s\n' "$SDK_SHA" "downloads/$SDK_NAME" | sha256sum -c -
if ! test -d work/openwrt-sdk; then
    mkdir work/openwrt-sdk
    tar --zstd -xf "downloads/$SDK_NAME" --strip-components=1 -C work/openwrt-sdk
fi
cd work/openwrt-sdk
echo '=== SDK feed versions ==='
cat feeds.conf.default
if ! test -e feeds/luci/luci.mk || ! test -e feeds/packages/utils/coremark/Makefile; then
    ./scripts/feeds update luci packages
fi
./scripts/feeds install coremark
# Give the local multithreaded build a distinct package revision so APK can
# replace the previously shipped single-threaded binary.
python3 - <<'PY'
from pathlib import Path
p=Path('feeds/packages/utils/coremark/Makefile')
s=p.read_text()
assert 'PKG_RELEASE:=1' in s or 'PKG_RELEASE:=2' in s
p.write_text(s.replace('PKG_RELEASE:=1','PKG_RELEASE:=2'))
PY
if ! test -d package/luci-theme-argon/.git; then
    git clone --depth 1 --branch v2.4.8 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
fi
test "$(git -C package/luci-theme-argon describe --tags --exact-match)" = v2.4.8
grep -q 'LUCI_MINIFY_UT:=0' package/luci-theme-argon/Makefile
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-theme-argon=m
CONFIG_PACKAGE_coremark=m
CONFIG_COREMARK_OPTIMIZE_O3=y
CONFIG_COREMARK_ENABLE_MULTITHREADING=y
CONFIG_COREMARK_NUMBER_OF_THREADS=16
# CONFIG_SIGNED_PACKAGES is not set
# CONFIG_ALL is not set
# CONFIG_ALL_KMODS is not set
# CONFIG_ALL_NONSHARED is not set
EOF
make defconfig
grep -Fx 'CONFIG_COREMARK_ENABLE_MULTITHREADING=y' .config
grep -Fx 'CONFIG_COREMARK_NUMBER_OF_THREADS=16' .config
# CoreMark does not declare these options in PKG_CONFIG_DEPENDS. Discard its
# old build stamp so changed compiler flags actually rebuild the binary.
make package/feeds/packages/coremark/clean
echo '=== Compiling CoreMark and Argon with matching OpenWrt SDK ==='
nice -n 10 make -j3 package/feeds/packages/coremark/compile package/luci-theme-argon/compile V=s
find bin/packages -type f \( -name 'coremark-*.apk' -o -name 'luci-theme-argon-*.apk' \) -print
mkdir -p "$ROOT/output/extra-packages"
find "$ROOT/output/extra-packages" -maxdepth 1 -type f -name 'coremark-*.apk' -delete
find bin/packages -type f \( -name 'coremark-*-r2.apk' -o -name 'luci-theme-argon-*.apk' \) -exec cp -t "$ROOT/output/extra-packages/" {} +
test "$(find "$ROOT/output/extra-packages" -name '*.apk' | wc -l)" -ge 2
ROOT="$ROOT" SDK_SHA="$SDK_SHA" python3 - <<'PY'
from pathlib import Path
import json,os,subprocess,hashlib
p=Path(os.environ['ROOT']); sdk=p/'work/openwrt-sdk'
def rev(path): return subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
data={'sdk':'OpenWrt 25.12.6 x86_64 GCC 14.3.0 musl','sdk_sha256':os.environ['SDK_SHA'],
      'luci_commit':rev(sdk/'feeds/luci'),'packages_commit':rev(sdk/'feeds/packages'),
      'argon_commit':rev(sdk/'package/luci-theme-argon'),'argon_tag':'v2.4.8',
      'coremark_multithreading':True,'coremark_threads':16,'coremark_package_release':2,
      'coremark_config':{line.split('=',1)[0]:line.split('=',1)[1] for line in (sdk/'.config').read_text().splitlines() if line.startswith('CONFIG_COREMARK_')},
      'coremark_makefile':(sdk/'feeds/packages/utils/coremark/Makefile').read_text(),
      'packages':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in (p/'output/extra-packages').glob('*.apk')}}
(p/'output/extra-packages/build-provenance.json').write_text(json.dumps(data,indent=2)+'\n')
PY
echo '=== EXTRA PACKAGES COMPLETE ==='

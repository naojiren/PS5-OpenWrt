#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
trap 'rc=$?; echo "LOADER_EXIT=$rc"; printf "%s\n" "$rc" > logs/loader.exit' EXIT
mkdir -p work/sdk downloads output logs
test -s downloads/ps5-payload-sdk.zip || curl -fL --retry 4 --connect-timeout 20 \
    https://github.com/ps5-payload-dev/sdk/releases/download/v0.44/ps5-payload-sdk.zip \
    -o downloads/ps5-payload-sdk.zip
echo '4d06eab777bb135705b5a6816688c9132efb246093fe606ac488ab6cf65ca5b0  downloads/ps5-payload-sdk.zip' | sha256sum -c -
unzip -q -o downloads/ps5-payload-sdk.zip -d work/sdk
test -d work/loader/.git || git clone --depth 1 https://github.com/ps5-linux/ps5-linux-loader.git work/loader
test "$(git -C work/loader rev-parse HEAD)" = 691e50f35953674cdeebe1306a01c7b7442cdc12
WIFI_PATCH="$ROOT/loader-patches/13.00-wifi-offset.patch"
if ! git -C work/loader apply --reverse --check "$WIFI_PATCH" 2>/dev/null; then
    git -C work/loader apply --check "$WIFI_PATCH"
    git -C work/loader apply "$WIFI_PATCH"
fi
export PS5_PAYLOAD_SDK="$ROOT/work/sdk/ps5-payload-sdk"
test -f "$PS5_PAYLOAD_SDK/toolchain/prospero.mk"
for count in $(seq 1 60); do
    command -v ld.lld >/dev/null && break
    sleep 5
done
command -v ld.lld
# Upstream misses a dependency between the generated HV header and kernel
# shellcode. A serial build preserves the required generation order.
make -C work/loader
cp work/loader/bin/ps5-linux-loader.elf output/ps5-linux-loader-13xx.elf
sha256sum output/ps5-linux-loader-13xx.elf downloads/ps5-payload-sdk.zip
echo '=== LOADER COMPLETE ==='

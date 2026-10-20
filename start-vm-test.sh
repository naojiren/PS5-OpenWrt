#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
ROOT=/home/ub/ps5-openwrt-13.00
cd "$ROOT"
test "$(cat logs/image.exit)" = 0
test ! -e work/qemu.pid || { echo 'Existing test VM needs inspection'; exit 1; }
sha256sum output/ps5-openwrt-25.12.6-13xx-experimental.img > output/image-before-test.sha256
if test -f work/network-probe.pid && kill -0 "$(cat work/network-probe.pid)" 2>/dev/null; then
    tr '\0' ' ' < "/proc/$(cat work/network-probe.pid)/cmdline" | grep -F network-probe-server.py >/dev/null
else
    nohup python3 network-probe-server.py > logs/network-probe.log 2>&1 < /dev/null &
    echo "$!" > work/network-probe.pid
fi
ACCEL=tcg
CPU=max
if test -r /dev/kvm && test -w /dev/kvm && grep -q '^CONFIG_CPU_SUP_INTEL=y' output/kernel.config; then ACCEL=kvm; CPU=host; fi
qemu-system-x86_64 -machine "q35,accel=$ACCEL" -cpu "$CPU" -m 1024 -smp 2 \
    -display none -serial none \
    -device virtio-serial-pci -chardev file,id=console0,path=logs/qemu-console.log \
    -device virtconsole,chardev=console0 \
    -monitor unix:work/qemu-monitor.sock,server=on,wait=off \
    -daemonize -pidfile work/qemu.pid -no-reboot \
    -kernel output/bzImage -initrd output/initrd.img \
    -append 'root=LABEL=ps5-openwrt rw rootwait console=hvc0 panic=0 initcall_blacklist=mp1_init,ps5_fan_init,ps5_led_init,ps5_buzzer_init,spcie_driver_init,tpcie_driver_init' \
    -drive file=output/ps5-openwrt-25.12.6-13xx-experimental.img,format=raw,if=virtio,snapshot=on \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:12222-:22,hostfwd=tcp:127.0.0.1:18080-:80 \
    -device virtio-net-pci,netdev=n0
printf 'TEST_VM_PID=%s ACCEL=%s\n' "$(cat work/qemu.pid)" "$ACCEL"

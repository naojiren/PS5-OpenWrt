**English** | [简体中文](BUILDING.zh-CN.md)

# Build notes

This repository preserves the build scripts, default configuration, patches, fan plugin source, and key modified files actually used for this release. Base Linux source, OpenWrt user space and SDK, the NXP driver, and other upstream projects are retrieved at pinned versions. See `sources.lock.json` for the version manifest.

## Build environment

The original build host runs Ubuntu and uses GCC, make, clang/lld, Docker, Python 3, OpenSSL, cpio, zstd, xz, parted, e2fsprogs, dosfstools, mtools, kmod, git, and QEMU. The SDK is OpenWrt 25.12.6 x86-64 with GCC 14.3.0 and musl.

The scripts retain the original build directory `/home/ub/ps5-openwrt-13.00` and unprivileged build user `ub`. Before using a different directory or username, update `ROOT`, `chown`, and the related paths consistently. Build SDK packages as an ordinary user; use root for rootfs creation, chroot operations, and image assembly where required by each script.

**A complete one-command rebuild on a fresh host has not been verified.** The original image was produced through separate build, signing, integration, and validation stages. Existence checks in the scripts preserve existing work and detect unfinished stages.

## Build stages

| Stage | Main entry points | Purpose |
| --- | --- | --- |
| PS5 kernel | `build-kernel.sh` | Fetch Linux 7.1.7 and pinned PS5 patches, apply the MTS receive-filter patch, then build the kernel and matching modules |
| Loader | `build-loader.sh` | Use the pinned loader commit and SDK 0.44; apply the 13.00 Wi-Fi extraction fix |
| SDK packages | `build-extra-packages.sh` | Build Argon and CoreMark configured for 16 threads by default |
| Base system | `prepare-rootfs.sh`, `build-rootfs.sh` | Prepare official OpenWrt user space, PS5 kernel module packages, initramfs, and the signing public key |
| Base integration | `integrate-extra-packages.sh` | Install extra packages, default network settings, and RTL8156B firmware |
| Wi-Fi | `build-wifi.sh`, `integrate-wifi.sh` | Build the PS5 IW620 driver; install wireless user space and the signed regulatory database |
| Fan control | `build-fan-plugin.sh`, `integrate-fan-plugin.sh` | Build upstream `ps5_control` and this project's LuCI plugin |
| OpenClash | `prepare-openclash-sources.sh`, `build-openclash.sh`, `prepare-openclash-runtime.sh`, `integrate-openclash.sh` | Build the interface, verify the official Mihomo release digest, and install matching runtime dependencies |
| Whole-disk image | `build-image.sh` | Create the external-drive GPT / ext4 / FAT image without writing to a physical disk |

The `integrate-*-revision.sh`, `integrate-lan-ap-revision.sh`, and `package-bridge-kernel.sh` scripts record migrations in the original build workspace. They depend on its snapshots or logs and are not suitable as the first command in a fresh directory.

## Corresponding source

- `source/linux/drivers/net/phy/mts/` contains the modified MTS files actually compiled. The reusable patch is in `kernel-patches/`.
- `source/ps5-linux-loader/` contains the modified loader files. The patches are in `loader-patches/`.
- `upstream/ps5-linux/linux.patch` and `base.config` correspond to the pinned PS5 Linux commit.
- `upstream/ps5-iw620/` contains the four Wi-Fi patches actually applied.
- `fan-plugin/src/ps5_control.c` comes from a pinned upstream commit. Interface and service code is in `fan-plugin/files/`.
- `source/coremark/Makefile` defines the 16-thread package built for this release.
- `configs/kernel.config` is the full kernel configuration shipped with the image.

## Package signing and firmware sources

Only `keys/ps5-openwrt.rsa.pub` is published. The private key is generated locally in the build environment and is absent from the repository and Release. For your own builds, generate your own signing key and install its matching public key in your image.

Mihomo uses the official stable prebuilt binary, checked against the official SHA-256 digest. OpenClash, the PS5 kernel, drivers, loader, and this project's plugin are built from the recorded sources. OpenWrt user space comes from the official release packages.

The loader extracts the PS5 IW620 runtime firmware from the console. That firmware is not distributed in this repository or the base image. AMD and Realtek firmware and wireless regulatory data retain their original distribution licenses; the relevant notices are preserved in the image.

`openclash-runtime-test.sh` and `lan-bridge-dhcp-test.sh` are the guest-side tests used during validation. Run them in a disposable test VM: the former checks core proxy forwarding, and the latter creates temporary network namespaces to verify upstream DHCP bridging.

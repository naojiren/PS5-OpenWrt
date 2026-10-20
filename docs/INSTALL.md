**English** | [简体中文](INSTALL-zh-CN.md) · [Project overview](../README.md)

# PS5-OpenWrt installation guide

For **PS5 Phat / Slim on firmware 13.00** that already meets the upstream Linux loader requirements. This image does not include jailbreak tools or instructions for upgrading the console's original firmware.

## Download

From [this release](https://github.com/naojiren/PS5-OpenWrt/releases/tag/v2026.10.20-r1003), download:

1. `PS5-OpenWrt-25.12.6-13.00-r1003-OpenClash.img.xz`: the whole-disk image; decompress it to obtain a **4 GiB** `.img` file.
2. `ps5-linux-loader-13xx.elf`: the loader with the 13.00 Wi-Fi fix. The same file is also included in the image.
3. `SHA256SUMS`: checksums for verifying your downloads.

The release also provides a source archive, build manifest, kernel configuration, and validation summary.

On Windows, compare these SHA-256 results with `SHA256SUMS`:

```powershell
Get-FileHash .\PS5-OpenWrt-25.12.6-13.00-r1003-OpenClash.img.xz -Algorithm SHA256
Get-FileHash .\ps5-linux-loader-13xx.elf -Algorithm SHA256
```

## Write the external drive

1. Prepare a USB drive of at least 64 GB, as recommended upstream. An external SSD is preferred.
2. Decompress `.img.xz`, then write the `.img` to the external drive with a whole-disk image tool such as balenaEtcher. **Writing erases the selected drive; verify the destination carefully.** Copying the files onto the drive is not sufficient to boot it.
3. Connect the drive to a rear PS5 USB-A port or a USB-C port supported by the upstream loader.
4. Following the upstream loader requirements, set USB power supply in rest mode to **Always** and disable HDMI Device Link.

The image already contains the kernel, initramfs, boot parameters, and ELF. The system partition is approximately 3.7 GiB; unused capacity on a larger drive is not expanded automatically.

## Boot OpenWrt

1. Enter your existing jailbreak and ELF loading environment. Use a clean session and leave kstuff / etaHEN unloaded for now.
2. Run `ps5-linux-loader-13xx.elf` from this release. If a payload manager stores an older ELF, replace that stored copy as well.
3. The console enters rest mode. Wait until the orange light stops blinking and remains steady, then press the power button to wake it.
4. After OpenWrt starts, find `PS5-OpenWrt` in your upstream router's device list to obtain its management IP.

This loader's Wi-Fi extraction fix targets **13.00**. Flashing only the image while still launching an older ELF can continue to produce incorrect Wi-Fi firmware.

## Login and default network

| Setting | Default |
| --- | --- |
| Management page | `http://<IP-assigned-by-upstream-router>/` |
| Username / password | `root` / `password` |
| SSH | Same IP, port `22` |
| Access point | `PS5-OpenWrt`, no password |
| Wireless | CN region, 5 GHz, channel 36, HE80 |
| Fallback direct-connection address | `172.31.55.1/24` |

For a fallback direct connection, set your computer to `172.31.55.2/24`, leave gateway and DNS blank, and open `http://172.31.55.1/`.

Wi-Fi and Ethernet belong to the same LAN bridge and receive IP addresses from the upstream router. The PS5's DHCP, DHCPv6, and RA servers are disabled by default. Reserve a DHCP address for the PS5 on the upstream router if you want to use it as a secondary gateway.

The firmware's LuCI interface currently defaults to Chinese. The menu labels below include the Chinese names for reference; these English documentation files do not change the firmware's language.

## OpenClash

Open **Services → OpenClash** (`服务 → OpenClash`), import your own subscription or YAML configuration, and enable it. OpenClash 0.48.002 and Mihomo Meta 1.19.32 are preinstalled, so downloading the core on first use is unnecessary. The image contains no subscription.

Set the clients that need proxy services to use the PS5's reserved DHCP address as both gateway and DNS. Connecting to the access point alone does not force traffic through the proxy: clients still follow the gateway settings supplied by upstream DHCP.

## Fan control, benchmarking, and USB Ethernet

- **System → PS5 Fan Control** (`系统 → PS5 风扇控制`): automatic thermal control starts at boot with a default target of 80°C. Select a target between 40–80°C or use manual full speed. Rebooting restores automatic mode. Arbitrary fan percentages and RPM readings are not exposed by the current interface.
- Run `coremark` over SSH for the default 16-thread benchmark. It does not run automatically at boot.
- The image includes the matching `r8152` driver and RTL8156B firmware. After connecting a USB Ethernet adapter, configure its role under **Network → Interfaces** (`网络 → 接口`). The built-in Ethernet port is preferred by default.

## Troubleshooting

- **No video:** first check whether the upstream router assigned an IP. You can also follow the upstream instructions to remove `video=DP-1:1920x1080@60` from `cmdline.txt` on the FAT partition and try again.
- **Wi-Fi is missing:** confirm that both the payload manager's stored ELF and the ELF actually launched match this release. Check whether `lib/nxp/pcieuartiw620_combo_v1.bin` was generated on the FAT partition.
- **Wi-Fi connects but clients receive no IP:** confirm that you are using the r1003 image, Ethernet is connected to the upstream network, and upstream DHCP works. This version includes the Ethernet receive-filter fix.
- **Generic upgrades:** do not install a generic x86 OpenWrt kernel, kmod, or sysupgrade image. This system requires the PS5-specific kernel and matching modules.
- **Booting again after shutdown:** return to your existing jailbreak procedure and run the Linux ELF again.

This is an experimental release. Wi-Fi bridging and DHCP have been confirmed on real hardware; 37 VM checks cover the pages, proxy core, and network features. Physical USB Ethernet compatibility, sustained thermal control, rest-mode resume, and complete power management remain subject to PS5 Linux hardware support.

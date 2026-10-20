# PS5-OpenWrt 安装说明

适用于已经满足上游 Linux 引导条件的 **PS5 Phat / Slim、13.00**。这份固件不包含越狱工具，也不指导升级主机原系统。

## 下载文件

从 [本版本 Release](https://github.com/naojiren/PS5-OpenWrt/releases/tag/v2026.10.20-r1003) 下载：

1. `PS5-OpenWrt-25.12.6-13.00-r1003-OpenClash.img.xz`：整盘固件，解压得到 **4 GiB** 的 `.img`。
2. `ps5-linux-loader-13xx.elf`：已加入本次 13.00 Wi-Fi 修复的引导器；镜像内也有同一文件。
3. `SHA256SUMS`：核对下载完整性。

Release 另外提供构建源码包、版本清单、内核配置和验证摘要。

Windows 可以运行以下命令核对文件摘要，并与 `SHA256SUMS` 比较：

```powershell
Get-FileHash .\PS5-OpenWrt-25.12.6-13.00-r1003-OpenClash.img.xz -Algorithm SHA256
Get-FileHash .\ps5-linux-loader-13xx.elf -Algorithm SHA256
```

## 写入外置盘

1. 准备上游推荐的至少 64GB USB 盘，优先使用外置 SSD。
2. 解压 `.img.xz`，使用 balenaEtcher 等整盘镜像工具，把 `.img` 写入外置盘。**写入会清空所选盘，请核对目标盘。** 只复制文件到盘上不能启动。
3. 将外置盘连接到 PS5 后置 USB-A，或上游支持的 USB-C 端口。
4. 按上游引导要求将待机 USB 供电设为“始终”，关闭 HDMI 设备联动。

镜像已有内核、initramfs、启动参数和 ELF。默认系统分区约 3.7 GiB，外置盘剩余容量不会自动扩展。

## 进入 OpenWrt

1. 按你已经可用的方式进入越狱和 ELF 加载环境，保持干净会话，暂不加载 kstuff / etaHEN。
2. 运行本 Release 提供的 `ps5-linux-loader-13xx.elf`。如果插件管理器保存的是旧 ELF，也要替换管理器中的文件。
3. 主机会进入待机；等橙灯停止闪烁并常亮后，再按电源键唤醒。
4. 启动 OpenWrt 后，在上级路由器设备列表中查找 `PS5-OpenWrt` 的地址。

本版加载器的 Wi-Fi 提取修正针对 **13.00**。只刷镜像却继续运行修复前的 ELF，仍可能提取错误的 Wi-Fi 固件。

## 登录和默认网络

| 项目 | 默认值 |
| --- | --- |
| 管理页面 | `http://上级路由器分配的IP/` |
| 用户名 / 密码 | `root` / `password` |
| SSH | 同一地址，端口 `22` |
| 热点 | `PS5-OpenWrt`，无密码 |
| 无线 | CN，5GHz，36 信道，HE80 |
| 备用直连地址 | `172.31.55.1/24` |

备用直连时，可把电脑设为 `172.31.55.2/24`，网关与 DNS 留空，再访问 `http://172.31.55.1/`。

Wi-Fi 和有线口在同一个 LAN 网桥内，均由上级路由器分配 IP；PS5 默认不开 DHCP、DHCPv6 或 RA 服务。建议在上级路由器为 PS5 设置固定 DHCP 租约，以便作为旁路由网关使用。

## OpenClash

进入 **“服务 → OpenClash”**，导入自己的订阅或 YAML 配置后启用。已预装 OpenClash 0.48.002 与 Mihomo Meta 1.19.32，不需要首次联网下载内核；镜像不包含订阅。

让需要代理的客户端使用 PS5 的固定 DHCP 地址作为网关和 DNS。仅连接热点时，客户端仍会按上级 DHCP 设置使用网关，不会自动被强制接管流量。

## 风扇、跑分和 USB 网卡

- **系统 → PS5 风扇控制**：开机自动温控，目标默认 80°C，可设置 40–80°C，或手动全速；重启恢复自动。当前接口不提供任意转速百分比和 RPM。
- 在 SSH 中运行 `coremark`，默认使用 16 线程；不会开机自动跑分。
- RTL8156B 已有配套 `r8152` 驱动与固件；接入 USB 网卡后，可在“网络 → 接口”配置用途。默认优先使用内置有线口。

## 常见问题

- **没有画面**：先检查上级路由器是否已分配地址。也可按上游说明从 FAT 分区 `cmdline.txt` 移除 `video=DP-1:1920x1080@60` 后重试。
- **Wi-Fi 不出现**：确认插件管理器和运行中的 ELF 均为本 Release 版本，并检查 FAT 分区是否生成 `lib/nxp/pcieuartiw620_combo_v1.bin`。
- **能连接热点但没有 IP**：确认使用 r1003 镜像、有线网口已连接上级网络、上级 DHCP 正常。该版本已集成有线接收过滤修复。
- **不能通用升级**：不要使用普通 x86 OpenWrt 的内核、kmod 或 sysupgrade；PS5 使用专用内核和对应模块。
- **关机后再次启动**：仍需进入原有越狱流程并运行 Linux ELF。

当前是实验版。Wi-Fi 桥接和 DHCP 已有实机确认；37 项虚拟机检查覆盖页面、代理核心与网络功能。实体 USB 网卡兼容性、长时间温控、待机唤醒和完整电源管理仍受 PS5 Linux 支持情况限制。

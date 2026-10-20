# PS5-OpenWrt

面向 **PS5 13.00** 的外置盘 OpenWrt 实验镜像，包含实际构建脚本、内核与引导器补丁、LuCI 风扇插件源码，以及固定版本的上游源码记录。

**[下载固件与引导器](https://github.com/naojiren/PS5-OpenWrt/releases/tag/v2026.10.20-r1003)** · **[安装说明](docs/INSTALL-zh-CN.md)** · **[构建说明](BUILDING.md)**

## 当前版本

| 组件 | 版本或配置 |
| --- | --- |
| OpenWrt | 25.12.6，中文 LuCI |
| PS5 Linux | 7.1.7-ps5-openwrt，kernel 7.1.7-r1003 |
| 默认主题 | Argon 2.4.8 |
| OpenClash | 0.48.002，源码编译 |
| Mihomo / Meta | 1.19.32，预装官方 x86-64 内核 |
| CoreMark | 默认 16 线程，不开机跑分 |
| Wi-Fi | IW620，CN、5GHz、36 信道、HE80 |
| USB 网卡 | 配套 r8152 驱动及 RTL8156B 固件 |
| 风扇 | 开机自动调速，默认目标 80°C；LuCI 支持调整目标和手动全速 |

## 默认设置

- 用户名：`root`；密码：`password`；SSH 端口：`22`。
- 管理地址由上级路由器 DHCP 分配，主机名为 `PS5-OpenWrt`。
- 备用直连地址：`172.31.55.1/24`。
- 热点名称：`PS5-OpenWrt`，无密码，默认启用。
- Wi-Fi 与有线网口加入同一个 `br-lan`，本机和无线客户端都使用上级 DHCP；本机默认不开 DHCP 服务。
- OpenClash 和 Mihomo 已预装。进入“服务 → OpenClash”导入自己的订阅或 YAML 配置后启用。

需要客户端使用 PS5 的旁路由/代理服务时，还需让客户端的网关和 DNS 指向 PS5。仅连接热点时，上级 DHCP 仍可能下发主路由为网关。

## 已包含的关键修复

1. **PS5 13.00 Wi-Fi 提取位置**：加载器提取起点前移 160 字节，并校验固件记录 CRC。
2. **无线自动启动**：识别 NXP 的 `mwiphy0`，驱动加载前应用 CN 地区，附带匹配的监管数据库和签名。
3. **桥接内核支持**：启用 `CONFIG_BRIDGE_VLAN_FILTERING=y`，与 OpenWrt 网络管理兼容。
4. **MTS 有线接收过滤**：移植上游的混杂模式和组播过滤修复，使网口能接收发给桥后无线客户端的单播回包。

其中 Wi-Fi 关联、上级 DHCP 获取和双向数据传输已在一台 CFI-2200 B01、13.00 主机上确认。当前镜像通过 **37 项虚拟机检查**，包括 Mihomo 实际 HTTP 代理转发、OpenClash 页面、TUN/TPROXY、上级 DHCP 桥接和 LuCI 风扇接口。完整记录见 [验证摘要](docs/validation-summary.json)；虚拟机结果不替代实体 USB 网卡、长时间温控及代理订阅的实机测试。

## 源码结构

- `build-*.sh`、`integrate-*.sh`：此版本使用的分阶段构建、集成脚本。
- `files/`：OpenWrt 网络、无线、启动服务等默认配置。
- `fan-plugin/`：LuCI 风扇插件和上游控制程序源码。
- `kernel-patches/`、`loader-patches/`：本项目使用的本地补丁。
- `source/`：编译时的 MTS、加载器源码快照及 CoreMark Makefile。
- `upstream/`：固定版本的 PS5 Linux 和 IW620 补丁。
- `configs/`：实际内核配置与 CoreMark 配置。
- `sources.lock.json`：上游仓库、提交、下载链接与校验值。
- `keys/`：发行 APK 的签名**公钥**；不包含签名私钥。

这是 PS5 专用内核与 OpenWrt 官方用户空间的组合，**不使用普通 x86 固件或通用 sysupgrade 替换内核**。当前版本从外置盘启动，冷启动后仍需通过已有的越狱和 Linux 引导流程进入系统。

## 上游与许可

感谢 [ps5-linux](https://github.com/ps5-linux)、[OpenWrt](https://openwrt.org/)、[OpenClash](https://github.com/vernesong/OpenClash)、[Mihomo](https://github.com/MetaCubeX/mihomo)、[NXP mwifiex](https://github.com/nxp-imx/mwifiex)、[Argon](https://github.com/jerrykuku/luci-theme-argon) 和 [CoreMark](https://github.com/eembc/coremark)。

本项目新增构建脚本和风扇插件界面按 GPL-2.0-only 发布。上游源码、补丁、内核、程序和固件保留各自许可证及权利声明，详见 [第三方来源](THIRD-PARTY-NOTICES.md)。

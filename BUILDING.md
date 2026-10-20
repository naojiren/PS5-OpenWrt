# 构建源码说明

本仓库同步了此发行版实际使用的构建脚本、默认配置、补丁、风扇插件源码和关键修改后文件。Linux 基础源码、OpenWrt 用户空间及 SDK、NXP 驱动和其他上游仓库通过固定版本获取，版本清单见 `sources.lock.json`。

## 构建环境

原构建宿主为局域网 Ubuntu，使用 GCC、make、clang/lld、Docker、Python 3、OpenSSL、cpio、zstd、xz、parted、e2fsprogs、dosfstools、mtools、kmod、git 和 QEMU。SDK 为 OpenWrt 25.12.6 x86-64 / GCC 14.3.0 / musl。

这些脚本保留原构建目录 `/home/ub/ps5-openwrt-13.00` 与普通构建用户 `ub`。使用其他目录或用户名时，先统一调整脚本中的 `ROOT`、`chown` 和相关路径。编译 SDK 包时使用普通用户；创建 rootfs、chroot 和镜像时按脚本要求使用 root。

**目前没有把“在全新宿主机上执行一条命令即可完整重建”列为已验证功能。** 原镜像由分阶段构建、签名、集成和检查得到；脚本中的存在性检查用于保留已有工作和发现未完成阶段。

## 构建阶段

| 阶段 | 主要入口 | 说明 |
| --- | --- | --- |
| PS5 内核 | `build-kernel.sh` | 获取 Linux 7.1.7 与固定 PS5 补丁，应用 MTS 接收过滤补丁，构建内核与配套模块 |
| 引导器 | `build-loader.sh` | 固定加载器提交与 SDK 0.44，应用 13.00 Wi-Fi 提取修正 |
| SDK 软件包 | `build-extra-packages.sh` | 编译 Argon 及默认 16 线程 CoreMark |
| 基础系统 | `prepare-rootfs.sh`、`build-rootfs.sh` | 官方 OpenWrt 用户空间、PS5 内核模块包、initramfs 和签名公钥 |
| 基础集成 | `integrate-extra-packages.sh` | 安装附加包、默认网络和 RTL8156B 固件 |
| Wi-Fi | `build-wifi.sh`、`integrate-wifi.sh` | 编译 PS5 IW620 驱动、安装无线用户空间与签名监管数据库 |
| 风扇 | `build-fan-plugin.sh`、`integrate-fan-plugin.sh` | 构建上游 `ps5_control` 和本项目 LuCI 插件 |
| OpenClash | `prepare-openclash-sources.sh`、`build-openclash.sh`、`prepare-openclash-runtime.sh`、`integrate-openclash.sh` | 编译界面、验证官方 Mihomo 发布摘要，安装匹配用户空间依赖 |
| 整盘镜像 | `build-image.sh` | 创建外置盘 GPT / ext4 / FAT 镜像，不写物理磁盘 |

`integrate-*-revision.sh`、`integrate-lan-ap-revision.sh`、`package-bridge-kernel.sh` 记录原构建中的版本迁移。这些脚本依赖原工作区的快照或日志，不能作为全新目录的首个入口直接运行。

## 对照源码

- `source/linux/drivers/net/phy/mts/` 是实际编译的 MTS 修改后文件；通用补丁位于 `kernel-patches/`。
- `source/ps5-linux-loader/` 是本次修改后的加载器文件；补丁位于 `loader-patches/`。
- `upstream/ps5-linux/linux.patch` 与 `base.config` 对应固定 PS5 Linux 提交。
- `upstream/ps5-iw620/` 是实际应用的四个 Wi-Fi 补丁。
- `fan-plugin/src/ps5_control.c` 来自固定上游提交；界面及服务代码位于 `fan-plugin/files/`。
- `source/coremark/Makefile` 为本次 16 线程包使用的构建定义。
- `configs/kernel.config` 为实际交付的完整内核配置。

## 包签名与固件来源

仓库仅公开 `keys/ps5-openwrt.rsa.pub`。私钥由构建环境本地生成，不在仓库或 Release 中；自行构建应使用自己的签名密钥并在自己的镜像内安装对应公钥。

Mihomo 使用官方稳定版预编译二进制，并校验官方发布的 SHA-256；OpenClash、PS5 内核、驱动、加载器和本项目插件按记录的源码构建。OpenWrt 用户空间来自官方发行包。

PS5 IW620 运行时固件由引导器从主机提取，未随仓库或基础镜像发布。AMD、Realtek 和无线监管数据沿用原始分发许可；镜像内保留相应说明文件。

`openclash-runtime-test.sh` 与 `lan-bridge-dhcp-test.sh` 是实际验证使用的客户机测试。它们应在可丢弃的测试 VM 中运行；前者验证核心代理转发，后者创建临时网络命名空间验证上级 DHCP 桥接。

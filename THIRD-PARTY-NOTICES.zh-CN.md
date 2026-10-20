[English](THIRD-PARTY-NOTICES.md) | **简体中文**

# 第三方源码与组件

本项目新增构建脚本和风扇插件界面使用根目录的 GPL-2.0-only 许可。该许可不替代以下上游文件、程序、固件和数据的许可；原始作者和权利归属保持不变。

| 组件 | 来源 |
| --- | --- |
| Linux 7.1.7 | https://www.kernel.org/ ，GPL-2.0-only / 按各文件 SPDX 标记 |
| PS5 Linux 补丁 | https://github.com/ps5-linux/ps5-linux-patches |
| PS5 Linux 加载器 | https://github.com/ps5-linux/ps5-linux-loader |
| PS5 IW620 补丁 | https://github.com/ps5-linux/ps5-linux-mwifiex |
| NXP mwifiex | https://github.com/nxp-imx/mwifiex |
| PS5 控制程序 | https://github.com/ps5-linux/ps5-linux-tools |
| OpenWrt 及 SDK | https://openwrt.org/ ，用户空间组件各自适用其许可证 |
| OpenClash | https://github.com/vernesong/OpenClash ，许可文本见 `LICENSES/OpenClash-LICENSE` |
| Mihomo | https://github.com/MetaCubeX/mihomo ，许可文本见 `LICENSES/Mihomo-LICENSE` |
| Argon | https://github.com/jerrykuku/luci-theme-argon |
| CoreMark | https://github.com/eembc/coremark |

固定提交、软件包版本、原始下载地址与摘要见 `sources.lock.json` 和 `docs/build-manifest.json`。仓库中的 `source/`、`upstream/` 文件用于保留本次构建的对应源码与补丁，不能据此改写上游的权利声明。

镜像内 AMD / Realtek 固件和监管数据库保留原始分发许可文件。仓库不包含从 PS5 提取的 IW620 固件、签名私钥、SSH 密钥、订阅配置或个人诊断记录。

**English** | [简体中文](THIRD-PARTY-NOTICES.zh-CN.md)

# Third-party source and components

The build scripts and fan plugin interface added by this project use the GPL-2.0-only license in the repository root. That license does not replace the licenses of the upstream files, programs, firmware, and data below. Original authorship and ownership notices remain unchanged.

| Component | Source |
| --- | --- |
| Linux 7.1.7 | https://www.kernel.org/ — GPL-2.0-only / per-file SPDX identifiers |
| PS5 Linux patches | https://github.com/ps5-linux/ps5-linux-patches |
| PS5 Linux loader | https://github.com/ps5-linux/ps5-linux-loader |
| PS5 IW620 patches | https://github.com/ps5-linux/ps5-linux-mwifiex |
| NXP mwifiex | https://github.com/nxp-imx/mwifiex |
| PS5 control tools | https://github.com/ps5-linux/ps5-linux-tools |
| OpenWrt and SDK | https://openwrt.org/ — user-space components retain their individual licenses |
| OpenClash | https://github.com/vernesong/OpenClash — license text in `LICENSES/OpenClash-LICENSE` |
| Mihomo | https://github.com/MetaCubeX/mihomo — license text in `LICENSES/Mihomo-LICENSE` |
| Argon | https://github.com/jerrykuku/luci-theme-argon |
| CoreMark | https://github.com/eembc/coremark |

Pinned commits, package versions, original download URLs, and digests are recorded in `sources.lock.json` and `docs/build-manifest.json`. Files in `source/` and `upstream/` preserve corresponding source and patches for this build; their inclusion does not change upstream rights or notices.

AMD / Realtek firmware and the regulatory database retain their original distribution license files in the image. The repository contains no IW620 firmware extracted from a PS5, signing private keys, SSH keys, subscription configurations, or personal diagnostic records.

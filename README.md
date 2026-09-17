# immortalwrt-Actions

使用 GitHub Actions 云编译 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)（master 分支，x86/64 generic）固件。

## 内置软件

P@SSW@LL、OpenClash、Tailscale、KMS(vlmcsd)、Lucky、ZeroTier、SoftEther VPN 全套、PushBot、tcpdump、SNMP、Zabbix Agent、WireGuard，以及完整 LuCI Web 界面，本固件主要为PVE定制，增加qemu-ga。

## 使用

Actions → **ImmortalWrt Builder** → Run workflow。编译约 2–3 小时，产物在该次运行的 Artifacts（`ImmortalWrt_firmware_*`），并自动发布到 Releases（保留最近 3 个）。

## 自定义

- `.config`：软件包选择（已在本地源码树 `make defconfig` 两轮幂等校验）
- `feeds.conf.default`：软件源
- `diy-part1.sh`：feeds 更新前（第三方插件）
- `diy-part2.sh`：feeds 更新后（IP/主机名等）

基于 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 模板。

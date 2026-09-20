# immortalwrt-Actions

使用 GitHub Actions 云编译 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)（master，x86/64 generic）固件。基于 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 模板。

- 源码版本：ImmortalWrt SNAPSHOT `r41059-3e246256ce`（随 master 更新）
- 内核：Linux 6.18.44
- 目标：x86/64 generic（BIOS + EFI）
- Web：LuCI master（默认简体中文）

## 默认定制

| 项 | 值 |
|---|---|
| 默认 LAN IP | `192.168.10.1/24` |
| 默认主机名 | `StarNetWrt` |
| 时区 | Asia/Shanghai（CST-8，含 zoneinfo-asia） |
| 连接数上限 | `net.netfilter.nf_conntrack_max=165535` |
| Kernel 分区 | 256 MiB |
| RootFS 分区 | 512 MiB |

## 内置软件与版本

> 版本以实际编译产物的 `*.manifest` 为准；下表对应 Release `2026.09.17-1205`，源码随 master 滚动，后续构建版本号可能更新。

### LuCI 应用

| 软件 | 版本 | 说明 |
|---|---|---|
| luci-app-openclash | 0.47.156 | OpenClash 代理 |
| luci-app-passwall | 26.9.9-r1 | PassWall 代理 |
| luci-app-tailscale-community | 26.252.03150 | Tailscale 组网 |
| luci-app-zerotier | 26.252.03150 | ZeroTier 组网 |
| luci-app-softethervpn | 26.252.03150 | SoftEther VPN（server/client/bridge） |
| luci-proto-wireguard | 26.252.03150 | WireGuard 协议支持 |
| luci-app-vlmcsd | 26.252.03150 | KMS 激活服务 |
| luci-app-lucky | 2.2.2-r1 | Lucky（动态域名/端口转发等） |
| luci-app-pushbot | 5.17-r23 | 多渠道消息推送 |
| luci-app-turboacc | 1.4-r1 | 流量转发加速/BBR/FullCONE |
| luci-app-upnp | 26.252.03150 | UPnP（miniupnpd-nftables） |
| luci-app-nlbwmon | 26.252.03150 | 流量带宽统计 |
| luci-app-advanced-reboot | 1.1.2-r6 | 高级重启/备用分区 |
| luci-app-filemanager | 26.252.03150 | 文件管理 |
| luci-app-ramfree | 26.252.03150 | 释放内存 |
| luci-app-tcpdump | 1.0-r2 | 抓包 |
| luci-app-snmpd | 26.252.03150 | SNMP |
| luci-app-zabbix-agent | 1.0.0-r1 | Zabbix Agent 配置界面 |
| luci-app-wificalling-location-gateway | 1.4.0-r1 | Wi-Fi Calling + WLOC 定位网关 |

### 后端 / 核心组件

| 软件 | 版本 |
|---|---|
| tailscale | 1.102.2-r1 |
| zerotier | 1.16.2-r1 |
| softethervpn5（server/client/bridge/libs） | 5.2.5188-r1 |
| wireguard-tools / kmod-wireguard | 1.0.20260223-r2 / 6.18.44-r1 |
| vlmcsd | 2020.03.30~e5990804-r8 |
| lucky | 2.27.2-r1 |
| xray-core | 26.3.27-r1 |
| sing-box | 1.12.25-r1 |
| chinadns-ng | 2025.08.09-r1 |
| haproxy | 3.4.2-r1 |
| shadowsocks-rust（sslocal/ssserver） | 1.24.0-r1 |
| miniupnpd-nftables | 2.3.9-r3 |
| nlbwmon | 2025.06.02~29236be6-r2 |
| qemu-ga | 10.1.3-r3 |
| zabbix-agentd | 7.0.30-r1 |
| snmpd-nossl | 5.9.5.2-r2 |
| tcpdump | 4.99.6-r1 |
| curl | 8.21.0-r1 |
| wget-ssl | 1.25.0-r5 |
| openssh-client / -client-utils / -sftp-server / -keygen | 10.5_p1-r1 |
| kmod-nft-offload / kmod-tcp-bbr | 6.18.44-r1 |
| kmod-nft-fullcone | 6.18.44.2023.05.17~07d93b62-r3 |
| zoneinfo-asia | 2026c-r1 |
| rpcd-mod-rpcsys | 2026.07.19~e37ed9d8-r1 | Wi-Fi Calling 网关 rpcd 依赖 |

> PassWall 默认不含 NaiveProxy（规避其 gn 主机工具在云编译上的构建问题）。
>
> Wi-Fi Calling Location Gateway 为 Rust 项目，因固件源码树无 Rust 编译基建，构建时下载官方 pinned 预编译 x86_64 IPK（v1.4.0-r1，sha256 校验）解包进 rootfs；二进制 static-pie 零动态库依赖。两个服务默认 enabled=0，在 LuCI 启用后生效。

## 固件产物

仅生成 squashfs 与虚拟机镜像（**不生成 ext4 镜像**）：

- `immortalwrt-x86-64-generic-squashfs-combined.img.gz`（BIOS）
- `immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz`（EFI）
- `immortalwrt-x86-64-generic-squashfs-combined.qcow2`（PVE/KVM，BIOS）
- `immortalwrt-x86-64-generic-squashfs-combined-efi.qcow2`（PVE/KVM，EFI）
- 另含 rootfs、kernel.bin、manifest、sha256sums 等

## 使用

Actions → **ImmortalWrt Builder** → Run workflow。编译约 2–3 小时，产物在该次运行的 Artifacts（`ImmortalWrt_firmware_*`），并自动发布到 Releases（保留最近 3 个）。刷写或启动前用 `sha256sums` 校验。

## 自定义

- `.config`：软件包选择（本地源码树 `make defconfig` 两轮幂等校验）
- `feeds.conf.default`：软件源
- `diy-part1.sh`：feeds 更新前（第三方插件 clone）
- `diy-part2.sh`：feeds 更新后（生成 files 覆盖：默认 IP/主机名/时区、conntrack、SoftEther procd 包装、pushbot/zabbix 启用）

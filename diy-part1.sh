#!/bin/bash
#
# immortalwrt-Actions DIY part 1 (Before Update feeds)
# 加入 ImmortalWrt 官方 feed 之外的第三方 LuCI 应用
#
mkdir -p package/community
pushd package/community >/dev/null
  # Lucky：同仓含 luci-app-lucky 界面与 lucky 预编译二进制包，需拆到两个目录
  rm -rf _lucky-repo luci-app-lucky lucky
  git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git _lucky-repo
  cp -r _lucky-repo/luci-app-lucky luci-app-lucky
  cp -r _lucky-repo/lucky lucky
  rm -rf _lucky-repo
  # PushBot 多渠道推送（仓库根即 OpenWrt 包）
  rm -rf luci-app-pushbot
  git clone --depth 1 -b master https://github.com/zzsj0928/luci-app-pushbot.git luci-app-pushbot
  # tcpdump LuCI（老式 luasrc，依赖 luci-compat）
  rm -rf luci-app-tcpdump
  git clone --depth 1 https://github.com/KFERMercer/luci-app-tcpdump.git luci-app-tcpdump
  # Zabbix agent LuCI（后端 zabbix-agentd 来自 packages feed）
  rm -rf luci-app-zabbix-agent
  git clone --depth 1 https://github.com/zzxym/luci-app-zabbix-agent.git luci-app-zabbix-agent
  # wrtbwmon：基于 iptables 的流量统计（供 PushBot 客户端流量使用，自动拉 iptables-nft）
  rm -rf _wrtbwmon-repo wrtbwmon
  git clone --depth 1 https://github.com/brvphoenix/wrtbwmon.git _wrtbwmon-repo
  cp -r _wrtbwmon-repo/wrtbwmon wrtbwmon
  rm -rf _wrtbwmon-repo
  # TurboACC：Flow Offload / BBR / FullCONE 加速（默认只拉 ImmortalWrt 有的
  # kmod-nft-offload / kmod-tcp-bbr / kmod-nft-fullcone，不碰 Lean 专属 SFE）
  rm -rf _turboacc-repo luci-app-turboacc
  git clone --depth 1 https://github.com/chenmozhijin/luci-app-turboacc.git _turboacc-repo
  cp -r _turboacc-repo/luci-app-turboacc luci-app-turboacc
  rm -rf _turboacc-repo
popd >/dev/null

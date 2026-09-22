#!/bin/bash
#
# immortalwrt-Actions DIY part 1 (Before Update feeds)
# 加入 ImmortalWrt 官方 feed 之外的第三方 LuCI 应用
#
# 所有第三方源固定到“已验证 commit SHA”，防止上游 master 漂移导致补丁失配
# （v9 失败教训）。升级第三方版本：改下方 *_SHA，本地验证后再触发编译。
set -e

# ── 已验证的第三方源 commit ──
LUCKY_SHA=c1730565c6df4ab30d345cf73584f03f5cc7bc8f
PUSHBOT_SHA=c92ce9e4aefb19409ad2c2f9c5e83466a76f44af
TCPDUMP_SHA=958650ee4dc57b5d7b987ace47c608aaf179dce0
ZABBIX_SHA=2a01e4c4a5fe3f92879f1ff3dff0780dc0821b47
TURBOACC_SHA=530092c532839efb96e9f328d34dbf3adff4b557
WRTBWMON_SHA=f82f9b393842d2113c3253a4902af50bfc757e1a

# clone 并检出到指定 SHA，校验失败即中止构建
pin_clone() {
	local url="$1" dir="$2" sha="$3"
	rm -rf "$dir"
	git clone --depth 1 "$url" "$dir" >/dev/null 2>&1
	git -C "$dir" fetch --depth 1 origin "$sha" >/dev/null 2>&1
	git -C "$dir" checkout -q FETCH_HEAD
	if [ "$(git -C "$dir" rev-parse HEAD)" != "$sha" ]; then
		echo "pin_clone failed: $url @ $sha" >&2
		exit 1
	fi
}

mkdir -p package/community
pushd package/community >/dev/null
  # Lucky：同仓含 luci-app-lucky 界面与 lucky 预编译二进制包，需拆到两个目录
  pin_clone https://github.com/gdy666/luci-app-lucky.git _lucky-repo "$LUCKY_SHA"
  rm -rf luci-app-lucky lucky
  cp -r _lucky-repo/luci-app-lucky luci-app-lucky
  cp -r _lucky-repo/lucky lucky
  rm -rf _lucky-repo
  # PushBot 多渠道推送（仓库根即 OpenWrt 包）
  pin_clone https://github.com/zzsj0928/luci-app-pushbot.git luci-app-pushbot "$PUSHBOT_SHA"
  # tcpdump LuCI（老式 luasrc，依赖 luci-compat）
  pin_clone https://github.com/KFERMercer/luci-app-tcpdump.git luci-app-tcpdump "$TCPDUMP_SHA"
  # Zabbix agent LuCI（后端 zabbix-agentd 来自 packages feed）
  pin_clone https://github.com/zzxym/luci-app-zabbix-agent.git luci-app-zabbix-agent "$ZABBIX_SHA"
  # TurboACC：Flow Offload / BBR / FullCONE 加速（默认只拉 ImmortalWrt 有的
  # kmod-nft-offload / kmod-tcp-bbr / kmod-nft-fullcone，不碰 Lean 专属 SFE）
  pin_clone https://github.com/chenmozhijin/luci-app-turboacc.git _turboacc-repo "$TURBOACC_SHA"
  rm -rf luci-app-turboacc
  cp -r _turboacc-repo/luci-app-turboacc luci-app-turboacc
  rm -rf _turboacc-repo
  # wrtbwmon：iptables 记账后端，供 PushBot 客户端流量统计
  pin_clone https://github.com/brvphoenix/wrtbwmon.git _wrtbwmon-repo "$WRTBWMON_SHA"
  rm -rf wrtbwmon
  cp -r _wrtbwmon-repo/wrtbwmon wrtbwmon
  rm -rf _wrtbwmon-repo
popd >/dev/null

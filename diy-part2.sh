#!/bin/bash
#
# immortalwrt-Actions DIY part 2 (After Update feeds)
# 在构建期写入 rootfs 覆盖文件（此时 cwd = openwrt/）
#
set -e

F="$PWD/files"
mkdir -p "$F/etc/init.d" "$F/etc/uci-defaults"

############################################################
# SoftEther VPN Server：界面启用后 NOT Running
# 原因：luci-app-softethervpn 自带的 /etc/init.d/softethervpn 是非 procd
#       脚本，直接在只读的 /usr/libexec/softethervpn 里跑 daemon，
#       无法写入 vpn_server.config，进程随即退出；且调用了已删除的 fw3。
#       官方后端包提供的 procd 服务 softethervpnserver 才是正解
#       （在可写的 /var/softethervpn 中运行）。
# 做法：把界面使用的同名 init 替换为“受 LuCI 开关控制的 procd 包装器”。
############################################################
cat > "$F/etc/init.d/softethervpn" <<'INITEOF'
#!/bin/sh /etc/rc.common
#
# Wrapper: LuCI 开关 UCI softethervpn.@softether[0].enable
#  -> 官方 procd 服务 softethervpnserver
#
START=99
STOP=10

start() {
	[ "$(uci -q get softethervpn.@softether[0].enable)" = "1" ] || return 0
	/etc/init.d/softethervpnserver start
}

stop() {
	/etc/init.d/softethervpnserver stop
}
INITEOF
chmod 755 "$F/etc/init.d/softethervpn"

############################################################
# 首次开机自定义：时区/中文 + pushbot/zabbix 默认启用
############################################################
cat > "$F/etc/uci-defaults/99-immortalwrt-custom" <<'UCIEOF'
#!/bin/sh

# softether 包装器加入开机序列（是否真起仍由界面开关控制）
[ -x /etc/init.d/softethervpn ] && /etc/init.d/softethervpn enable

# 时区：Asia/Shanghai (UTC+8)。CST-8 为 POSIX 写法，zonename 供 LuCI/zoneinfo 使用
uci -q set system.@system[0].timezone='CST-8'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q commit system

# LuCI 默认简体中文
uci -q set luci.main.lang='zh_cn'
uci -q commit luci

# PushBot：默认 pushbot_enable=0 会导致启动即自杀
if uci -q show pushbot >/dev/null 2>&1; then
	uci -q set pushbot.pushbot.pushbot_enable='1'
	uci -q commit pushbot
	/etc/init.d/pushbot enable
	/etc/init.d/pushbot restart
fi

# Zabbix agentd：UCI general.enabled 默认 0，
# init 读到 0 直接退出，表现为 active with no instances
if uci -q show zabbix_agentd >/dev/null 2>&1; then
	uci -q set zabbix_agentd.general.enabled='1'
	uci -q commit zabbix_agentd
	/etc/init.d/zabbix_agentd enable
	/etc/init.d/zabbix_agentd start
fi

exit 0
UCIEOF
chmod 755 "$F/etc/uci-defaults/99-immortalwrt-custom"

echo "custom files generated:"
find "$F" -type f -exec ls -l {} \;
exit 0

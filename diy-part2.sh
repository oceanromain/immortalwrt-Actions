#!/bin/bash
#
# immortalwrt-Actions DIY part 2 (After Update feeds)
# 在构建期写入 rootfs 覆盖文件并微调第三方源码（此时 cwd = openwrt/）
#
set -e

F="$PWD/files"
mkdir -p "$F/etc/init.d" "$F/etc/uci-defaults" "$F/etc/sysctl.d"

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
# 连接数调优：nf_conntrack_max=165535（START=11 sysctl 读取 /etc/sysctl.d/*.conf；
# nf_conntrack 由 kmodloader 在更早阶段加载，hotplug 也会按接口重放 net.* 项）
############################################################
cat > "$F/etc/sysctl.d/99-conntrack.conf" <<'SYSCTL_EOF'
net.netfilter.nf_conntrack_max=165535
SYSCTL_EOF

############################################################
# PushBot 客户端流量：强制优先使用 wrtbwmon
# PushBot 原逻辑优先探测 nlbwmon；修好 nlbwmon 后它反而不会用 wrtbwmon，
# 故在其 init_traffic_source 探测最前面插入 wrtbwmon 优先块。
############################################################
PB="$PWD/package/community/luci-app-pushbot/root/usr/bin/pushbot/pushbot"
python3 - "$PB" <<'PYEOF'
import sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
# 上游 master 新版探测块（nlbw 优先，wrtbwmon 次之）
old=("\tif command -v nlbw >/dev/null 2>&1; then\n"
     "\t\ttraffic_source=\"nlbw\"\n"
     "\telif [ -f \"/usr/sbin/wrtbwmon\" ]; then\n"
     "\t\ttraffic_source=\"wrtbw\"\n"
     "\tfi")
assert s.count(old)==1, f"anchor count={s.count(old)}"
# 交换顺序：wrtbwmon 优先
new=("\t# Prefer wrtbwmon over nlbwmon for client traffic\n"
     "\tif [ -f \"/usr/sbin/wrtbwmon\" ]; then\n"
     "\t\ttraffic_source=\"wrtbw\"\n"
     "\telif command -v nlbw >/dev/null 2>&1; then\n"
     "\t\ttraffic_source=\"nlbw\"\n"
     "\tfi")
s=s.replace(old,new)
open(p,'w',encoding='utf-8').write(s)
PYEOF
grep -q 'Prefer wrtbwmon over nlbwmon' "$PB" || { echo "patch pushbot traffic source failed" >&2; exit 1; }

############################################################
# wrtbwmon：关闭其自带常驻 daemon
# 常驻 daemon 每次 update 会用 iptables -Z 清零计数器，与 PushBot 的按需
# 取数互相偷数据。改为仅由 PushBot 以 one-shot 方式调用 wrtbwmon。
############################################################
WCFG="$PWD/package/community/wrtbwmon/net/etc/config/wrtbwmon"
if [ -f "$WCFG" ]; then
	sed -i "s/option enabled '1'/option enabled '0'/" "$WCFG"
fi
grep -q "option enabled '0'" "$WCFG" || { echo "patch wrtbwmon config failed" >&2; exit 1; }

############################################################
# 首次开机自定义：时区/中文 + nlbwmon/pushbot/zabbix 默认启用
############################################################
cat > "$F/etc/uci-defaults/99-immortalwrt-custom" <<'UCIEOF'
#!/bin/sh

# softether 包装器加入开机序列（是否真起仍由界面开关控制）
[ -x /etc/init.d/softethervpn ] && /etc/init.d/softethervpn enable

# 默认主机名 StarNetWrt
uci -q set system.@system[0].hostname='StarNetWrt'

# 时区：Asia/Shanghai (UTC+8)。CST-8 为 POSIX 写法，zonename 供 LuCI/zoneinfo 使用
uci -q set system.@system[0].timezone='CST-8'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q commit system

# 默认 LAN IP：192.168.1.1 -> 192.168.10.1/24
# 新版为 CIDR list ipaddr，需先删旧值再 add_list（在 config_generate 之后执行）
uci -q delete network.lan.ipaddr
uci -q add_list network.lan.ipaddr='192.168.10.1/24'
uci -q commit network

# LuCI 默认简体中文
uci -q set luci.main.lang='zh_cn'
uci -q commit luci

# nlbwmon：官方包默认不启用开机服务，导致 LuCI 流量页无数据
/etc/init.d/nlbwmon enable
/etc/init.d/nlbwmon start

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

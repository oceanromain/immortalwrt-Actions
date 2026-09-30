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

############################################################
# Zabbix Agent LuCI：适配当前 ImmortalWrt master
# 上游 zzxym commit 2a01e4c 使用已废弃的客户端 LuCI 菜单路径，且 UCI 名写成
# zabbix-agentd；官方 zabbix-agentd 实际使用 zabbix_agentd。构建期将其修正为
# 现代 LuCI 菜单/ACL/视图，并增加 UCI -> zabbix_agentd.conf 的同步脚本。
############################################################
ZB_UI="$PWD/package/community/luci-app-zabbix-agent"
test -f "$ZB_UI/Makefile"

# 清理上游旧 LuCI/错误 UCI 文件
rm -rf "$ZB_UI/htdocs/luci-static/resources/controller" \
       "$ZB_UI/htdocs/luci-static/resources/menu.d" \
       "$ZB_UI/htdocs/luci-static/resources/view/zabbix-agentd"
rm -f "$ZB_UI/root/etc/config/zabbix-agentd" \
      "$ZB_UI/root/etc/init.d/zabbix-agentd-config" \
      "$ZB_UI/root/usr/libexec/rpcd/zabbix-agentd" \
      "$ZB_UI/root/usr/share/rpcd/acl.d/zabbix-agentd.json" \
      "$ZB_UI/po/zh_Hans/zabbix-agentd.po"

mkdir -p "$ZB_UI/root/usr/share/luci/menu.d" \
         "$ZB_UI/root/usr/share/rpcd/acl.d" \
         "$ZB_UI/root/etc/init.d" \
         "$ZB_UI/root/etc/uci-defaults" \
         "$ZB_UI/htdocs/luci-static/resources/view/zabbix-agent" \
         "$ZB_UI/po/zh_Hans"

cat > "$ZB_UI/root/usr/share/luci/menu.d/luci-app-zabbix-agent.json" <<'EOF'
{
	"admin/services/zabbix-agent": {
		"title": "Zabbix Agent",
		"action": {
			"type": "view",
			"path": "zabbix-agent/general"
		},
		"depends": {
			"acl": [ "luci-app-zabbix-agent" ],
			"uci": {
				"zabbix_agentd": true
			}
		}
	}
}
EOF

cat > "$ZB_UI/root/usr/share/rpcd/acl.d/luci-app-zabbix-agent.json" <<'EOF'
{
	"luci-app-zabbix-agent": {
		"description": "Grant access to Zabbix agent configuration",
		"read": {
			"uci": [ "zabbix_agentd" ],
			"ubus": {
				"service": [ "list" ]
			}
		},
		"write": {
			"uci": [ "zabbix_agentd" ],
			"ubus": {
				"rc": [ "init" ]
			}
		}
	}
}
EOF

cat > "$ZB_UI/htdocs/luci-static/resources/view/zabbix-agent/general.js" <<'EOF'
'use strict';
'require form';
'require rpc';
'require uci';
'require view';

const callRcInit = rpc.declare({
	object: 'rc',
	method: 'init',
	params: [ 'name', 'action' ],
	expect: { result: false }
});

return view.extend({
	render: function() {
		let m, s, o;

		m = new form.Map('zabbix_agentd', _('Zabbix Agent'),
			_('Manage Zabbix agent service and connection settings.'));

		s = m.section(form.NamedSection, 'general', 'zabbix_agentd');
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'server', _('Zabbix server'),
			_('Comma-separated passive Zabbix server IP addresses or hostnames.'));
		o.default = '127.0.0.1';

		o = s.option(form.Value, 'server_active', _('Active Zabbix server'),
			_('Zabbix active-check target, e.g. 127.0.0.1:10051. Leave empty to disable active checks.'));
		o.placeholder = '127.0.0.1:10051';

		o = s.option(form.Value, 'hostname', _('Hostname'),
			_('Optional unique host name. Defaults to the system hostname.'));

		o = s.option(form.Value, 'listen_ip', _('Listen IP'));
		o.datatype = 'ipaddr';
		o.default = '0.0.0.0';

		o = s.option(form.Value, 'listen_port', _('Listen port'));
		o.datatype = 'port';
		o.default = '10050';

		o = s.option(form.ListValue, 'debug_level', _('Debug level'));
		o.value('0', _('Critical'));
		o.value('1', _('Error'));
		o.value('2', _('Warning'));
		o.value('3', _('Notice'));
		o.value('4', _('Debug'));
		o.default = '3';

		o = s.option(form.Value, 'timeout', _('Timeout'),
			_('Agent check timeout in seconds (1-30).'));
		o.datatype = 'range(1,30)';
		o.default = '3';

		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		return view.prototype.handleSaveApply.apply(this, arguments).then(function() {
			return callRcInit('zabbix-agentd-sync', 'restart');
		}).then(function() {
			return callRcInit('zabbix_agentd', 'restart');
		});
	}
});
EOF

cat > "$ZB_UI/root/etc/init.d/zabbix-agentd-sync" <<'EOF'
#!/bin/sh /etc/rc.common

START=59
NAME=zabbix-agentd-sync
UCI_CONFIG=zabbix_agentd
TARGET_CONF=/etc/zabbix_agentd.conf

generate_config() {
	local enabled server server_active hostname listen_ip listen_port timeout debug_level

	config_load "$UCI_CONFIG"
	config_get_bool enabled general enabled 0
	[ "$enabled" = "1" ] || return 0

	config_get server general server "127.0.0.1"
	config_get server_active general server_active ""
	config_get hostname general hostname ""
	config_get listen_ip general listen_ip "0.0.0.0"
	config_get listen_port general listen_port "10050"
	config_get timeout general timeout "3"
	config_get debug_level general debug_level "3"

	local tmp
	tmp=$(mktemp /tmp/zabbix_agentd.conf.XXXXXX)
	{
		echo '# Generated by luci-app-zabbix-agent'
		echo 'PidFile=/var/run/zabbix-agent/zabbix_agentd.pid'
		echo 'LogType=system'
		echo 'StartAgents=1'
		echo 'User=zabbix-agent'
		echo "Server=$server"
		[ -n "$server_active" ] && echo "ServerActive=$server_active"
		if [ -n "$hostname" ]; then
			echo "Hostname=$hostname"
		else
			echo 'HostnameItem=system.hostname'
		fi
		echo "ListenIP=$listen_ip"
		echo "ListenPort=$listen_port"
		echo "Timeout=$timeout"
		echo "DebugLevel=$debug_level"
		echo 'Include=/usr/share/zabbix_agentd.openwrt-params.d/'
		echo 'Include=/etc/zabbix_agentd.conf.d/*.conf'
	} > "$tmp"
	chmod 0644 "$tmp"
	mv "$tmp" "$TARGET_CONF"
}

start() {
	generate_config
}

restart() {
	generate_config
}

reload() {
	generate_config
}
EOF
chmod 755 "$ZB_UI/root/etc/init.d/zabbix-agentd-sync"

cat > "$ZB_UI/root/etc/uci-defaults/99-luci-zabbix-agent" <<'EOF'
#!/bin/sh

[ -f /etc/config/zabbix_agentd ] || exit 0
. /lib/functions.sh

set_default() {
	local value
	config_get value general "$1"
	[ -n "$value" ] || uci set zabbix_agentd.general."$1"="$2"
}

config_load zabbix_agentd
uci set zabbix_agentd.general.enabled='1'
set_default server '127.0.0.1'
set_default hostname ''
set_default listen_ip '0.0.0.0'
set_default listen_port '10050'
set_default timeout '3'
set_default debug_level '3'
uci commit zabbix_agentd

/etc/init.d/zabbix-agentd-sync enable
/etc/init.d/zabbix_agentd enable
/etc/init.d/zabbix-agentd-sync start
/etc/init.d/zabbix_agentd restart

exit 0
EOF
chmod 755 "$ZB_UI/root/etc/uci-defaults/99-luci-zabbix-agent"

cat > "$ZB_UI/po/zh_Hans/zabbix-agent.po" <<'EOF'
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"

msgid "Zabbix Agent"
msgstr "Zabbix Agent"

msgid "Manage Zabbix agent service and connection settings."
msgstr "管理 Zabbix Agent 服务和连接设置。"

msgid "Enable"
msgstr "启用"

msgid "Zabbix server"
msgstr "Zabbix 服务器"

msgid "Comma-separated passive Zabbix server IP addresses or hostnames."
msgstr "被动模式允许的 Zabbix 服务器 IP 或主机名，多个值用逗号分隔。"

msgid "Active Zabbix server"
msgstr "主动模式 Zabbix 服务器"

msgid "Zabbix active-check target, e.g. 127.0.0.1:10051. Leave empty to disable active checks."
msgstr "主动检查目标，例如 127.0.0.1:10051；留空则关闭主动检查。"

msgid "Hostname"
msgstr "主机名"

msgid "Optional unique host name. Defaults to the system hostname."
msgstr "可选的唯一主机名；默认使用系统主机名。"

msgid "Listen IP"
msgstr "监听 IP"

msgid "Listen port"
msgstr "监听端口"

msgid "Debug level"
msgstr "调试级别"

msgid "Critical"
msgstr "严重"

msgid "Error"
msgstr "错误"

msgid "Warning"
msgstr "警告"

msgid "Notice"
msgstr "通知"

msgid "Debug"
msgstr "调试"

msgid "Timeout"
msgstr "超时"

msgid "Agent check timeout in seconds (1-30)."
msgstr "Agent 检查超时时间，单位秒（1-30）。"
EOF

echo "custom files generated:"
find "$F" -type f -exec ls -l {} \;
exit 0

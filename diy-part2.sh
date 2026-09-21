#!/bin/bash
#
# immortalwrt-Actions DIY part 2 (After Update feeds)
# 在构建期写入 rootfs 覆盖文件（此时 cwd = openwrt/）
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
# Wi-Fi Calling Location Gateway（第三方 Rust 插件）
# 我们的源码树无 Rust 编译基建，故下载官方 pinned 预编译 x86_64 IPK，
# 校验 sha256 后把 data 段解进 files/（二进制为 static-pie，零动态库依赖）。
############################################################
WLG_URL="https://github.com/smthdagg/wificalling-location-gateway/releases/download/v1.4.0/wificalling-location-gateway_1.4.0-r1_x86_64.ipk"
WLG_SHA="093f3ee4f97809dce3b3c91a321216a690a3b027d86641244f5bba6535290a0a"
WLG_TMP="$(mktemp -d)"
curl -fsSL --retry 3 -o "$WLG_TMP/wlg.ipk" "$WLG_URL"
echo "$WLG_SHA  $WLG_TMP/wlg.ipk" | sha256sum -c -
mkdir -p "$WLG_TMP/ar"
tar xzf "$WLG_TMP/wlg.ipk" -C "$WLG_TMP/ar"
tar xzf "$WLG_TMP/ar/data.tar.gz" -C "$F"

# Fix: iPhone Safari 访问 http://<lan>/wloc-ca.mobileconfig 回 403 Forbidden。
# 根因：uhttpd 要求文件带“其他可读”位（file.c: !(st_mode & S_IROTH) -> 403），
# 而 export-mobileconfig.sh 从不 chmod，守护进程 umask 偏严时文件为 0600。
# 补丁：生成 profile 落盘后强制 chmod 0644（对每次重新生成都生效）。
EXPS="$F/usr/sbin/export-mobileconfig.sh"
# 唯一锚点：清理临时文件那行；在其后插入 chmod，保证 0644
if grep -q '^rm -f "\$OUT.unsigned"' "$EXPS"; then
	sed -i '/^rm -f "\$OUT.unsigned"/a chmod 0644 "$OUT"' "$EXPS"
fi
grep -q '^chmod 0644 "\$OUT"' "$EXPS" || { echo "patch export-mobileconfig.sh failed" >&2; exit 1; }

rm -rf "$WLG_TMP"
echo "wificalling-location-gateway integrated into files/ (mobileconfig 0644 patched)"

############################################################
# 首次开机自定义：时区/中文 + pushbot/zabbix 默认启用
############################################################
cat > "$F/etc/uci-defaults/99-immortalwrt-custom" <<'UCIEOF'
#!/bin/sh

# softether 包装器加入开机序列（是否真起仍由界面开关控制）
[ -x /etc/init.d/softethervpn ] && /etc/init.d/softethervpn enable

# Wi-Fi Calling / WLOC：加入开机序列。默认 enabled=0，开机不真起；
# 用户在 LuCI 启用后由 procd 拉起
[ -x /etc/init.d/wificalling-gateway ] && /etc/init.d/wificalling-gateway enable
[ -x /etc/init.d/wloc-service ] && /etc/init.d/wloc-service enable

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

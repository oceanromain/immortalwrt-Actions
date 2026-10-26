#!/bin/bash
# firewall4 自带 fullcone 补丁刷新：适配上游 2026-10-26 快照
# 背景：immortalwrt master 提交 e2e50c9dc4 将 firewall4 升至 2026-10-26~bac1d656，
#   新版 fw4.uc 把 if (zone.masq || zone.masq6) 拆成 IPv4/IPv6 两个独立分支，
#   源码树自带的 001-firewall4-add-support-for-fullcone-nat.patch 第 8 个 hunk 失配，
#   OpenWrt 补丁流程禁用 fuzz，直接导致 firewall4 编译失败（run 40334194069）。
# 策略：仅命中该失配版本时整包替换为刷新版（已在 bac1d656 上 fuzz=0 验证），
#   其他版本一律 no-op；上游自行修复或再次 bump 后本脚本自动旁路。
set -e

FW4="package/network/config/firewall4"
PATCH="$FW4/patches/001-firewall4-add-support-for-fullcone-nat.patch"

test -f "$FW4/Makefile" || { echo "firewall4 Makefile 缺失，目录结构异常" >&2; exit 1; }

if ! grep -q "^PKG_SOURCE_DATE:=2026-10-26$" "$FW4/Makefile" \
   || ! grep -q "^PKG_SOURCE_VERSION:=bac1d656e09b48e542f860844fe91cbba82abae2$" "$FW4/Makefile"; then
	echo "firewall4 非已知失配版本(2026-10-26/bac1d656)，跳过补丁刷新"
	exit 0
fi

test -f "$PATCH" || { echo "预期的上游 fullcone 补丁不存在：$PATCH" >&2; exit 1; }

cat > "$PATCH" <<'PATCH_EOF'
From aa3b56e289fba7425e649a608c333622ffd9c367 Mon Sep 17 00:00:00 2001
From: Syrone Wong <wong.syrone@gmail.com>
Date: Sat, 9 Apr 2022 13:24:19 +0800
Subject: [PATCH] firewall4: add fullcone support

fullcone is drop-in replacement of masq for non-udp traffic

add runtime fullcone rule check, disable it globally if fullcone expr is
invalid

defaults.fullcone and defaults.fullcone6 are switches for IPv4 and IPv6
respectively, most IPv6 traffic do NOT need this FullCone NAT functionality.

Renew: ZiMing Mo <msylgj@immortalwrt.org>
---
 root/etc/config/firewall                      |  2 ++
 root/usr/share/firewall4/templates/ruleset.uc | 16 ++++++++++++++--
 .../firewall4/templates/zone-fullcone.uc      |  4 ++++
 root/usr/share/ucode/fw4.uc                   | 69 ++++++++++++++++++-
 4 files changed, 89 insertions(+), 4 deletions(-)
 create mode 100644 root/usr/share/firewall4/templates/zone-fullcone.uc

--- a/root/etc/config/firewall
+++ b/root/etc/config/firewall
@@ -5,6 +5,10 @@ config defaults
 	option forward		REJECT
 # Uncomment this line to disable ipv6 rules
 #	option disable_ipv6	1
+	option flow_offloading	1
+	option flow_offloading_hw	1
+	option fullcone		1
+	option fullcone6	0
 
 config zone
 	option name		lan
--- a/root/usr/share/firewall4/templates/ruleset.uc
+++ b/root/usr/share/firewall4/templates/ruleset.uc
@@ -330,6 +330,12 @@ table inet fw4 {
 {%   for (let redirect in fw4.redirects(`dstnat_${zone.name}`)): %}
 		{%+ include("redirect.uc", { fw4, zone, redirect }) %}
 {%   endfor %}
+{%   if (zone.masq && fw4.default_option("fullcone")): %}
+		{%+ include("zone-fullcone.uc", { fw4, zone, family: 4, direction: "dstnat" }) %}
+{%   endif %}
+{%   if (zone.masq6 && fw4.default_option("fullcone6")): %}
+		{%+ include("zone-fullcone.uc", { fw4, zone, family: 6, direction: "dstnat" }) %}
+{%   endif %}
 {%   fw4.includes('chain-append', `dstnat_${zone.name}`) %}
 	}
 
@@ -340,20 +346,26 @@ table inet fw4 {
 {%   for (let redirect in fw4.redirects(`srcnat_${zone.name}`)): %}
 		{%+ include("redirect.uc", { fw4, zone, redirect }) %}
 {%   endfor %}
-{%   if (zone.masq): %}
+{%   if (zone.masq && !fw4.default_option("fullcone")): %}
 {%    for (let saddrs in zone.masq4_src_subnets): %}
 {%     for (let daddrs in zone.masq4_dest_subnets): %}
 		{%+ include("zone-masq.uc", { fw4, zone, family: 4, saddrs, daddrs }) %}
 {%     endfor %}
 {%    endfor %}
 {%   endif %}
-{%   if (zone.masq6): %}
+{%   if (zone.masq6 && !fw4.default_option("fullcone6")): %}
 {%    for (let saddrs in zone.masq6_src_subnets): %}
 {%     for (let daddrs in zone.masq6_dest_subnets): %}
 		{%+ include("zone-masq.uc", { fw4, zone, family: 6, saddrs, daddrs }) %}
 {%     endfor %}
 {%    endfor %}
 {%   endif %}
+{%   if (zone.masq && fw4.default_option("fullcone")): %}
+		{%+ include("zone-fullcone.uc", { fw4, zone, family: 4, direction: "srcnat" }) %}
+{%   endif %}
+{%   if (zone.masq6 && fw4.default_option("fullcone6")): %}
+		{%+ include("zone-fullcone.uc", { fw4, zone, family: 6, direction: "srcnat" }) %}
+{%   endif %}
 {%   fw4.includes('chain-append', `srcnat_${zone.name}`) %}
 	}
 
diff --git a/root/usr/share/firewall4/templates/zone-fullcone.uc b/root/usr/share/firewall4/templates/zone-fullcone.uc
new file mode 100644
index 0000000..77d9806
--- /dev/null
+++ b/root/usr/share/firewall4/templates/zone-fullcone.uc
@@ -0,0 +1,4 @@
+{# /usr/share/firewall4/templates/zone-fullcone.uc #}
+		meta nfproto {{ fw4.nfproto(family) }} fullcone comment "!fw4: Handle {{
+		zone.name
+}} {{ fw4.nfproto(family, true) }} fullcone NAT {{ direction }} traffic"
--- a/root/usr/share/ucode/fw4.uc
+++ b/root/usr/share/ucode/fw4.uc
@@ -1,3 +1,5 @@
+// /usr/share/ucode/fw4.uc
+
 const fs = require("fs");
 const uci = require("uci");
 const ubus = require("ubus");
@@ -489,6 +491,25 @@ function nft_try_hw_offload(devices) {
 	return (rc == 0);
 }
 
+function nft_try_fullcone() {
+	let nft_test =
+		'add table inet fw4-fullcone-test; ' +
+		'add chain inet fw4-fullcone-test dstnat { ' +
+			'type nat hook prerouting priority -100; policy accept; ' +
+			'fullcone; ' +
+		'}; ' +
+		'add chain inet fw4-fullcone-test srcnat { ' +
+			'type nat hook postrouting priority -100; policy accept; ' +
+			'fullcone; ' +
+		'}; ';
+	let cmd = sprintf("/usr/sbin/nft -c '%s' 2>/dev/null", replace(nft_test, "'", "'\\''"));
+	let ok = system(cmd) == 0;
+	if (!ok) {
+		warn("nft_try_fullcone: cmd "+ cmd + "\n");
+	}
+	return ok;
+}
+
 
 return {
 	read_kernel_version: function() {
@@ -873,6 +894,18 @@ return {
 			warn(`[!] ${msg}\n`);
 	},
 
+	myinfo: function(fmt, ...args) {
+		if (getenv("QUIET"))
+			return;
+
+		let msg = sprintf(fmt, ...args);
+
+		if (getenv("TTY"))
+			warn(`\033[32m${msg}\033[m\n`);
+		else
+			warn(`[I] ${msg}\n`);
+	},
+
 	get: function(sid, opt) {
 		return this.cursor.get("firewall", sid, opt);
 	},
@@ -1056,6 +1089,21 @@ return {
 		}
 	},
 
+	myinfo_section: function(s, msg) {
+		if (s[".name"]) {
+			if (s.name)
+				this.myinfo("Section %s (%s) %s", this.section_id(s[".name"]), s.name, msg);
+			else
+				this.myinfo("Section %s %s", this.section_id(s[".name"]), msg);
+		}
+		else {
+			if (s.name)
+				this.myinfo("ubus %s (%s) %s", s.type || "rule", s.name, msg);
+			else
+				this.myinfo("ubus %s %s", s.type || "rule", msg);
+		}
+	},
+
 	parse_policy: function(val) {
 		return this.parse_enum(val, [
 			"accept",
@@ -1495,6 +1543,7 @@ return {
 			"dnat",
 			"snat",
 			"masquerade",
+			"fullcone",
 			"accept",
 			"reject",
 			"drop"
@@ -1966,6 +2015,8 @@ return {
 		}
 
 		let defs = this.parse_options(data, {
+			fullcone: [ "bool", "0" ],
+			fullcone6: [ "bool", "0" ],
 			input: [ "policy", "drop" ],
 			output: [ "policy", "drop" ],
 			forward: [ "policy", "drop" ],
@@ -2000,6 +2051,11 @@ return {
 
 		delete defs.syn_flood;
 
+		if (!nft_try_fullcone()) {
+			delete defs.fullcone;
+			warn("nft_try_fullcone failed, disable fullcone globally\n");
+		}
+
 		this.state.defaults = defs;
 	},
 
@@ -2245,10 +2301,23 @@ return {
 		zone.related_subnets = related_subnets;
 		zone.related_physdevs = related_physdevs;
 
-		if (zone.masq || zone.masq6)
+		if (zone.masq) {
 			zone.dflags.snat = true;
+			if (this.state.defaults.fullcone) {
+				zone.dflags.dnat = true;
+				this.myinfo_section(data, "IPv4 fullcone enabled for zone '" + zone.name + "'");
+			}
+		}
+
+		if (zone.masq6) {
+			zone.dflags.snat = true;
+			if (this.state.defaults.fullcone6) {
+				zone.dflags.dnat = true;
+				this.myinfo_section(data, "IPv6 fullcone enabled for zone '" + zone.name + "'");
+			}
+		}
 
-		if ((zone.auto_helper && !(zone.masq || zone.masq6)) || length(zone.helper)) {
+		if ((zone.auto_helper && !(zone.masq || zone.masq6 || this.state.defaults.fullcone || this.state.defaults.fullcone6)) || length(zone.helper)) {
 			zone.dflags.helper = false;
 
 			for (let helper in (length(zone.helper) ? zone.helper : this.state.helpers)) {
PATCH_EOF

# 结果锚点校验（缺任一即中止构建）
grep -q "@@ -2245,10 +2301,23 @@" "$PATCH"
grep -q "IPv4 fullcone enabled" "$PATCH"
grep -q "IPv6 fullcone enabled" "$PATCH"
grep -q "zone-fullcone.uc" "$PATCH"
echo "firewall4 fullcone 补丁已刷新（适配 2026-10-26/bac1d656）"

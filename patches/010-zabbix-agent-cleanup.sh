#!/bin/bash
# Zabbix Agent LuCI 兼容层收尾：
# 清理上游 zzxym/luci-app-zabbix-agent（锁定 2a01e4c）残留的旧版文件——
#   - 旧客户端菜单路径 htdocs/luci-static/resources/menu.d（现代 LuCI 不读取）
#   - 旧 UCI 名 zabbix-agentd（官方后端是 zabbix_agentd）
# 现代实现由 custom/luci-app-zabbix-agent/ 覆盖层提供（先于本补丁应用）。
set -e

ZB="package/community/luci-app-zabbix-agent"
test -f "$ZB/Makefile"

rm -rf "$ZB/htdocs/luci-static/resources/controller" \
       "$ZB/htdocs/luci-static/resources/menu.d" \
       "$ZB/htdocs/luci-static/resources/view/zabbix-agentd"
rm -f "$ZB/root/etc/config/zabbix-agentd" \
      "$ZB/root/etc/init.d/zabbix-agentd-config" \
      "$ZB/root/usr/libexec/rpcd/zabbix-agentd" \
      "$ZB/root/usr/share/rpcd/acl.d/zabbix-agentd.json" \
      "$ZB/po/zh_Hans/zabbix-agentd.po"

# 覆盖层必须已生效（同时是编排器的顺序检查）
test -f "$ZB/root/usr/share/luci/menu.d/luci-app-zabbix-agent.json"
test -f "$ZB/htdocs/luci-static/resources/view/zabbix-agent/general.js"
test -x "$ZB/root/etc/init.d/zabbix-agentd-sync"

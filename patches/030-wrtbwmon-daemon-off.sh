#!/bin/bash
# wrtbwmon：关闭其自带常驻 daemon
# 常驻 daemon 每次 update 会用 iptables -Z 清零计数器，与 PushBot 的按需
# 取数互相偷数据。改为仅由 PushBot 以 one-shot 方式调用 wrtbwmon。
set -e

WCFG="$PWD/package/community/wrtbwmon/net/etc/config/wrtbwmon"
if [ -f "$WCFG" ]; then
	sed -i "s/option enabled '1'/option enabled '0'/" "$WCFG"
fi
grep -q "option enabled '0'" "$WCFG" || { echo "patch wrtbwmon config failed" >&2; exit 1; }

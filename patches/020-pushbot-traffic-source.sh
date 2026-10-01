#!/bin/bash
# PushBot 客户端流量：强制优先使用 wrtbwmon
# PushBot 原逻辑优先探测 nlbwmon；修好 nlbwmon 后它反而不会用 wrtbwmon，
# 故在其 init_traffic_source 探测块交换顺序：wrtbwmon 优先。
set -e

PB="$PWD/package/community/luci-app-pushbot/root/usr/bin/pushbot/pushbot"
python3 - "$PB" <<'PYEOF'
import sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
# 上游新版探测块（nlbw 优先，wrtbwmon 次之）
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

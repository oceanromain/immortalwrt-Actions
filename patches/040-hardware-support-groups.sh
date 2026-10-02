#!/bin/bash
# 对齐基干 hardware-support：sane-backends / tvheadend 的动态组所有权
# 基干 package/system/hardware-support 已显式占用 scanner=47、dvb=49 等组；
# pinned packages feed 里这两个包仍用无 id 的动态组名（:scanner / :dvb），
# scripts/metadata.pm 校验组名 id 不一致即令 prepare-tmpinfo 失败
# （Download package 步骤，make defconfig 阶段）。
# 修法与上游一致：组名补显式 id，并 DEPENDS 对应的 *-support 特性门控包。
# 幂等：feed pin 更新到已含修复时自动跳过。
set -e

FEED="$PWD/feeds/packages"

apply_edits() {
	local f="$1"
	[ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
	python3 - "$f" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
name = p.split('/')[-2]
edits = {
    "sane-backends": [
        ("PKG_RELEASE:=1\n", "PKG_RELEASE:=2\n"),
        ("  DEPENDS:=+libsane\n", "  DEPENDS:=scanner-support +libsane\n"),
        ("  USERID:=saned:scanner\n", "  USERID:=saned:scanner=47\n"),
    ],
    "tvheadend": [
        ("PKG_RELEASE:=1\n", "PKG_RELEASE:=2\n"),
        ("  USERID:=tvheadend:dvb\n", "  USERID:=tvheadend:dvb=49\n"),
        ("  DEPENDS:= \\\n\t+librt",
         "  DEPENDS:= \\\n\tdvb-support \\\n\t+librt"),
    ],
}[name]
changed = []
for old, new in edits:
    if new in s and old not in s:
        continue  # already fixed
    n = s.count(old)
    assert n == 1, f"{name}: anchor count={n} for {old!r}"
    s = s.replace(old, new)
    changed.append(old.split('\n')[0].strip())
open(p, 'w', encoding='utf-8').write(s)
print(name + ": " + (", ".join(changed) if changed else "already fixed"))
PYEOF
}

SANE="$FEED/utils/sane-backends/Makefile"
TVH="$FEED/multimedia/tvheadend/Makefile"

apply_edits "$SANE"
apply_edits "$TVH"

# 结果校验
grep -q 'DEPENDS:=scanner-support +libsane' "$SANE" || { echo "sane depends verify failed" >&2; exit 1; }
grep -q 'USERID:=saned:scanner=47' "$SANE" || { echo "sane userid verify failed" >&2; exit 1; }
grep -q 'USERID:=tvheadend:dvb=49' "$TVH" || { echo "tvheadend userid verify failed" >&2; exit 1; }
grep -q '^	dvb-support \\$' "$TVH" || { echo "tvheadend depends verify failed" >&2; exit 1; }
echo "hardware-support groups verified."

#!/bin/bash
# 对齐基干 hardware-support：sane-backends / tvheadend 的动态组所有权
# 基干 package/system/hardware-support 已显式占用 scanner=47、dvb=49 等组；
# 旧 packages feed 里这两个包仍用无 id 的动态组名（:scanner / :dvb），
# scripts/metadata.pm 校验组名 id 不一致即令 prepare-tmpinfo 失败
# （Download package 步骤，make defconfig 阶段）。
# 修法与上游一致：组名补显式 id，并 DEPENDS 对应的 *-support 特性门控包。
#
# 幂等规则（按语义，不按 PKG_RELEASE 数字）：
#   sane：USERID 含 scanner=47 且 DEPENDS 含 scanner-support → 已修好，整包跳过
#   tvh ：USERID 含 dvb=49 且 DEPENDS 含 dvb-support → 已修好，整包跳过
# 仅在未修好时改 USERID/DEPENDS，并用正则把 PKG_RELEASE:=N 升为 N+1。
set -e

FEED="$PWD/feeds/packages"

apply_edits() {
	local f="$1"
	[ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
	python3 - "$f" <<'PYEOF'
import re
import sys

p = sys.argv[1]
s = open(p, encoding="utf-8").read()
name = p.split("/")[-2]

def bump_pkg_release(text: str) -> str:
    m = re.search(r"(?m)^(PKG_RELEASE:=)(\d+)\s*$", text)
    assert m, f"{name}: PKG_RELEASE:=N not found"
    n = int(m.group(2))
    return text[: m.start(2)] + str(n + 1) + text[m.end(2) :]

if name == "sane-backends":
    already = ("USERID:=saned:scanner=47" in s) and ("scanner-support" in s)
    if already:
        print("sane-backends: already fixed")
        sys.exit(0)
    edits = [
        ("  DEPENDS:=+libsane\n", "  DEPENDS:=scanner-support +libsane\n"),
        ("  USERID:=saned:scanner\n", "  USERID:=saned:scanner=47\n"),
    ]
elif name == "tvheadend":
    already = ("USERID:=tvheadend:dvb=49" in s) and ("dvb-support" in s)
    if already:
        print("tvheadend: already fixed")
        sys.exit(0)
    edits = [
        ("  USERID:=tvheadend:dvb\n", "  USERID:=tvheadend:dvb=49\n"),
        (
            "  DEPENDS:= \\\n\t+librt",
            "  DEPENDS:= \\\n\tdvb-support \\\n\t+librt",
        ),
    ]
else:
    raise SystemExit(f"unknown package: {name}")

changed = []
for old, new in edits:
    if new in s and old not in s:
        continue  # this line already applied
    n = s.count(old)
    assert n == 1, f"{name}: anchor count={n} for {old!r}"
    s = s.replace(old, new)
    changed.append(old.split("\n")[0].strip())

if changed:
    s = bump_pkg_release(s)
    changed.insert(0, "PKG_RELEASE:+1")

open(p, "w", encoding="utf-8").write(s)
print(name + ": " + (", ".join(changed) if changed else "already fixed"))
PYEOF
}

SANE="$FEED/utils/sane-backends/Makefile"
TVH="$FEED/multimedia/tvheadend/Makefile"

apply_edits "$SANE"
apply_edits "$TVH"

# 结果校验（语义）
grep -q 'scanner-support' "$SANE" || { echo "sane depends verify failed" >&2; exit 1; }
grep -q 'USERID:=saned:scanner=47' "$SANE" || { echo "sane userid verify failed" >&2; exit 1; }
grep -q 'USERID:=tvheadend:dvb=49' "$TVH" || { echo "tvheadend userid verify failed" >&2; exit 1; }
grep -q 'dvb-support' "$TVH" || { echo "tvheadend depends verify failed" >&2; exit 1; }
echo "hardware-support groups verified."

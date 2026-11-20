#!/bin/bash
# gn [host]：ubuntu-22.04 自带 clang-14 不认 -std=c++23（只认 c++2b），
# 导致 feeds/packages/devel/gn host-compile 在 ninja 第一步失败
# （run 44663343124：error: invalid value 'c++23' in '-std=c++23'）。
# 修法：在 Host/Compile 前把 out/*.ninja 里的 -std=c++23 换成 -std=c++2b。
# clang-16+（ubuntu-24.04）本身支持 c++23，sed 无匹配时为 no-op，保持幂等。
set -e

MK="feeds/packages/devel/gn/Makefile"
if [ ! -f "$MK" ]; then
	echo "gn Makefile 不存在，跳过"
	exit 0
fi

if grep -q 'std=c++23/-std=c++2b' "$MK"; then
	echo "gn host cxx-std 补丁已存在"
	exit 0
fi

python3 - "$MK" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = """define Host/Compile
\t+$(NINJA) -C $(HOST_BUILD_DIR)/out gn
endef
"""
new = """define Host/Compile
\t# clang-14 (ubuntu-22.04) rejects -std=c++23; c++2b is the draft synonym it accepts.
\t# clang-16+ already accepts c++23 — sed becomes a no-op when the token is absent.
\tfind $(HOST_BUILD_DIR)/out -type f -name '*.ninja' -exec sed -i 's/-std=c++23/-std=c++2b/g' {} +
\t+$(NINJA) -C $(HOST_BUILD_DIR)/out gn
endef
"""
if old not in s:
    raise SystemExit(f"gn Makefile Host/Compile anchor miss (file changed upstream): {p}")
p.write_text(s.replace(old, new, 1), encoding="utf-8")
print("gn host: inject c++23→c++2b ninja rewrite before compile")
PY

grep -q 'std=c++23/-std=c++2b' "$MK" || { echo "gn patch verify failed" >&2; exit 1; }
echo "gn host cxx-std patch verified."

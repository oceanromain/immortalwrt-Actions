#!/bin/bash
#
# immortalwrt-Actions DIY part 2 (After Update feeds)
# 纯编排器，保持精简。文件内容分三处维护：
#   files/            rootfs 覆盖（模板原生机制，构建时由 workflow 整体 mv 进 openwrt/files）
#   custom/<包名>/     第三方包源码覆盖层（仓库里直接维护真实文件）
#   patches/*.sh      动态补丁（按文件名序执行，各自带锚点/结果校验）
# 本脚本不内嵌任何文件内容。cwd = openwrt/
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# files/：GitHub Web 编辑 / Contents API 会丢可执行位，这里统一兜底修正
F="$PWD/files"
if [ -d "$F" ]; then
	find "$F/etc/init.d" "$F/etc/uci-defaults" -type f -exec chmod 755 {} + 2>/dev/null || true
fi

############################################################
# 1. 应用第三方包覆盖层：custom/<包名>/ -> package/community/<包名>/
############################################################
shopt -s nullglob
for overlay in "$REPO_ROOT"/custom/*/; do
	pkg="$(basename "$overlay")"
	target="package/community/$pkg"
	test -d "$target" || { echo "overlay target missing: $target" >&2; exit 1; }
	cp -a "$overlay". "$target/"
	# 覆盖层内 init.d / uci-defaults 同样兜底可执行位
	find "$target/root/etc/init.d" "$target/root/etc/uci-defaults" -type f -exec chmod 755 {} + 2>/dev/null || true
	echo "overlay applied: $pkg"
done

############################################################
# 2. 依序运行动态补丁（补丁内部自带校验，失败即中止构建）
############################################################
for patch in "$REPO_ROOT"/patches/*.sh; do
	echo "patch: $(basename "$patch")"
	bash "$patch"
done

echo "diy-part2 done."
exit 0

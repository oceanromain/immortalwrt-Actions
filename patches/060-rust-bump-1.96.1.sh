#!/bin/bash
# rust host 编译修复：1.96.0 → 1.96.1
# 背景：feeds.conf.default 钉住的 immortalwrt/packages 6d68ffeb 中 lang/rust 为 1.96.0，
#   其 Makefile 设 llvm.download-ci-llvm=true，依赖 ci-artifacts.rust-lang.org 上按
#   rustc 源码 commit (ac68faa…) 存放的预编译 LLVM；Rust 官方定期清理旧构建工件，
#   1.96.0 的 rust-dev tar.xz 已 404（run 43910669430，2026-11-16），x.py 报
#   "failed to download llvm from ci"，rust [host] 失败导致 world Error 2。
# 策略：仅命中 1.96.0/release2/已知 hash 时把 Makefile 升到 1.96.1（immortalwrt/packages
#   master 已于 2026-11-11 经 "Merge Official Source" 合入，1.96.1 CI 工件实测 HTTP 200）；
#   其他版本一律 no-op，feed pin 前移后本脚本自动旁路。
set -e

MK="feeds/packages/lang/rust/Makefile"
test -f "$MK" || { echo "rust Makefile 缺失：$MK" >&2; exit 1; }

if ! grep -q '^PKG_VERSION:=1.96.0$' "$MK"; then
	echo "rust 非 1.96.0（当前 $(awk -F:= '/^PKG_VERSION:/{print $2}' "$MK")），跳过"
	exit 0
fi

grep -q '^PKG_RELEASE:=2$' "$MK" \
	|| { echo "rust 1.96.0 但 PKG_RELEASE 非预期，拒绝盲改" >&2; exit 1; }
grep -q '^PKG_HASH:=b99ce16cdf0ecfc761b585ac84d131b46733465a02f8ecd0ff2de9713c62ee09$' "$MK" \
	|| { echo "rust 1.96.0 PKG_HASH 与已知值不符，拒绝盲改" >&2; exit 1; }

sed -i \
	-e 's#^PKG_VERSION:=1.96.0$#PKG_VERSION:=1.96.1#' \
	-e 's#^PKG_RELEASE:=2$#PKG_RELEASE:=1#' \
	-e 's#^PKG_HASH:=b99ce16cdf0ecfc761b585ac84d131b46733465a02f8ecd0ff2de9713c62ee09$#PKG_HASH:=77a6ff3003a4ad0cb00697b043c879e3e1a15d945b1a1f63818903bfc3fa8b98#' \
	"$MK"

grep -q '^PKG_VERSION:=1.96.1$' "$MK" || { echo "rust 版本替换失败" >&2; exit 1; }
grep -q '^PKG_HASH:=77a6ff3003a4ad0cb00697b043c879e3e1a15d945b1a1f63818903bfc3fa8b98$' "$MK" \
	|| { echo "rust hash 替换失败" >&2; exit 1; }
echo "rust Makefile 已升至 1.96.1（CI LLVM 工件已验证存活）"

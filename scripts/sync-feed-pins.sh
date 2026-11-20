#!/usr/bin/env bash
#
# sync-feed-pins.sh — 官方 feed pin 跟随上游 tip，同时保持 URL^commit 可复现。
#
# 设计：
#   - 构建仍只用 feeds.conf.default 里钉死的 SHA（稳）
#   - 本脚本把 pin 对齐到 packages/luci/routing 的当前 tip（或显式 SHA）（新）
#   - 不自动改 diy-part1 第三方源；那是另一条升级线
#
# 用法：
#   scripts/sync-feed-pins.sh check              # 打印滞后；有漂移则 exit 2
#   scripts/sync-feed-pins.sh write              # 写回 feeds.conf.default = 上游 tip
#   scripts/sync-feed-pins.sh write \
#       --packages <sha> --luci <sha> --routing <sha>
#   scripts/sync-feed-pins.sh print-json         # 机器可读状态（CI 用）
#
# 环境：
#   FEEDS_CONF   默认仓库根 feeds.conf.default
#   GH_TOKEN     可选；gh api 限流时用
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEEDS_CONF="${FEEDS_CONF:-$ROOT/feeds.conf.default}"

PACKAGES_REPO="immortalwrt/packages"
LUCI_REPO="immortalwrt/luci"
ROUTING_REPO="openwrt/routing"
PACKAGES_REF="${PACKAGES_REF:-master}"
LUCI_REF="${LUCI_REF:-master}"
ROUTING_REF="${ROUTING_REF:-master}"

die() { echo "error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "需要命令：$1"
}

# 解析 feeds.conf.default 里 name -> full40 sha（无 pin 则空）
parse_pinned() {
  local name="$1"
  local line
  line="$(grep -E "^src-git[[:space:]]+${name}[[:space:]]+" "$FEEDS_CONF" || true)"
  [[ -n "$line" ]] || { echo ""; return 0; }
  if [[ "$line" =~ \^([0-9a-fA-F]{7,40})[[:space:]]*$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

resolve_head() {
  local repo="$1" ref="$2"
  local sha date subject
  # sha \t iso-date \t subject
  local meta
  meta="$(gh api "repos/${repo}/commits/${ref}" \
    --jq '[.sha, .commit.committer.date, (.commit.message|split("\n")[0])] | @tsv')"
  sha="${meta%%$'\t'*}"
  local rest="${meta#*$'\t'}"
  date="${rest%%$'\t'*}"
  subject="${rest#*$'\t'}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "无法解析 ${repo}@${ref} 的 commit"
  printf '%s\t%s\t%s\n' "$sha" "$date" "$subject"
}

expand_sha() {
  # 短 SHA -> 该 repo 上的完整 SHA；已是 40 位则原样校验存在性
  local repo="$1" sha="$2"
  [[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "非法 SHA：$sha"
  local full
  full="$(gh api "repos/${repo}/commits/${sha}" --jq '.sha')"
  [[ "$full" =~ ^[0-9a-f]{40}$ ]] || die "上游不存在：${repo}@${sha}"
  echo "$full"
}

fmt_row() {
  printf '  %-10s  pin=%-12s  tip=%-12s  tip_date=%s  %s\n' "$@"
}

cmd_status() {
  need_cmd gh
  need_cmd grep

  [[ -f "$FEEDS_CONF" ]] || die "找不到 $FEEDS_CONF"

  local pin_p pin_l pin_r
  pin_p="$(parse_pinned packages)"
  pin_l="$(parse_pinned luci)"
  pin_r="$(parse_pinned routing)"

  local tip_p tip_l tip_r
  tip_p="$(resolve_head "$PACKAGES_REPO" "$PACKAGES_REF")"
  tip_l="$(resolve_head "$LUCI_REPO" "$LUCI_REF")"
  tip_r="$(resolve_head "$ROUTING_REPO" "$ROUTING_REF")"

  local p_sha p_date p_subj l_sha l_date l_subj r_sha r_date r_subj
  IFS=$'\t' read -r p_sha p_date p_subj <<<"$tip_p"
  IFS=$'\t' read -r l_sha l_date l_subj <<<"$tip_l"
  IFS=$'\t' read -r r_sha r_date r_subj <<<"$tip_r"

  # 展开短 pin 便于比较
  local full_p full_l full_r
  full_p=""; full_l=""; full_r=""
  [[ -n "$pin_p" ]] && full_p="$(expand_sha "$PACKAGES_REPO" "$pin_p")"
  [[ -n "$pin_l" ]] && full_l="$(expand_sha "$LUCI_REPO" "$pin_l")"
  [[ -n "$pin_r" ]] && full_r="$(expand_sha "$ROUTING_REPO" "$pin_r")"

  echo "feeds.conf: $FEEDS_CONF"
  echo "upstream tips:"
  fmt_row packages "${full_p:-<none>}" "${p_sha:0:12}" "$p_date" "$p_subj"
  fmt_row luci     "${full_l:-<none>}" "${l_sha:0:12}" "$l_date" "$l_subj"
  fmt_row routing  "${full_r:-<none>}" "${r_sha:0:12}" "$r_date" "$r_subj"

  local drift=0
  [[ "$full_p" == "$p_sha" ]] || drift=1
  [[ "$full_l" == "$l_sha" ]] || drift=1
  [[ "$full_r" == "$r_sha" ]] || drift=1

  if [[ "$drift" -eq 0 ]]; then
    echo "status: in-sync"
    return 0
  fi
  echo "status: behind-upstream"
  return 2
}

cmd_print_json() {
  need_cmd gh
  need_cmd python3
  [[ -f "$FEEDS_CONF" ]] || die "找不到 $FEEDS_CONF"

  local pin_p pin_l pin_r
  pin_p="$(parse_pinned packages)"
  pin_l="$(parse_pinned luci)"
  pin_r="$(parse_pinned routing)"

  local tip_p tip_l tip_r
  tip_p="$(resolve_head "$PACKAGES_REPO" "$PACKAGES_REF")"
  tip_l="$(resolve_head "$LUCI_REPO" "$LUCI_REF")"
  tip_r="$(resolve_head "$ROUTING_REPO" "$ROUTING_REF")"

  local p_sha p_date p_subj l_sha l_date l_subj r_sha r_date r_subj
  IFS=$'\t' read -r p_sha p_date p_subj <<<"$tip_p"
  IFS=$'\t' read -r l_sha l_date l_subj <<<"$tip_l"
  IFS=$'\t' read -r r_sha r_date r_subj <<<"$tip_r"

  local full_p full_l full_r
  full_p=""; full_l=""; full_r=""
  [[ -n "$pin_p" ]] && full_p="$(expand_sha "$PACKAGES_REPO" "$pin_p")"
  [[ -n "$pin_l" ]] && full_l="$(expand_sha "$LUCI_REPO" "$pin_l")"
  [[ -n "$pin_r" ]] && full_r="$(expand_sha "$ROUTING_REPO" "$pin_r")"

  FEEDS_CONF="$FEEDS_CONF" PIN_P="$full_p" PIN_L="$full_l" PIN_R="$full_r" \
  TIP_P="$p_sha" TIP_L="$l_sha" TIP_R="$r_sha" \
  DATE_P="$p_date" DATE_L="$l_date" DATE_R="$r_date" \
  SUB_P="$p_subj" SUB_L="$l_subj" SUB_R="$r_subj" \
  python3 - <<'PY'
import json, os
pins = {
  "packages": os.environ.get("PIN_P") or None,
  "luci": os.environ.get("PIN_L") or None,
  "routing": os.environ.get("PIN_R") or None,
}
tips = {
  "packages": {"sha": os.environ["TIP_P"], "date": os.environ["DATE_P"], "subject": os.environ["SUB_P"]},
  "luci": {"sha": os.environ["TIP_L"], "date": os.environ["DATE_L"], "subject": os.environ["SUB_L"]},
  "routing": {"sha": os.environ["TIP_R"], "date": os.environ["DATE_R"], "subject": os.environ["SUB_R"]},
}
behind = any(pins[k] != tips[k]["sha"] for k in pins)
print(json.dumps({
  "feeds_conf": os.environ["FEEDS_CONF"],
  "pins": pins,
  "tips": tips,
  "behind_upstream": behind,
}, ensure_ascii=False, indent=2))
PY
}

write_feeds_conf() {
  local p_sha="$1" l_sha="$2" r_sha="$3" synced_at="$4"
  cat > "$FEEDS_CONF" <<EOF
# Official ImmortalWrt/OpenWrt feeds — pinned with OpenWrt src-git URL^commit.
# Keeps builds reproducible; bump with: scripts/sync-feed-pins.sh write
# Last synced (UTC): ${synced_at}
# packages ${p_sha}
# luci     ${l_sha}
# routing  ${r_sha}
src-git packages https://github.com/immortalwrt/packages.git^${p_sha}
src-git luci https://github.com/immortalwrt/luci.git^${l_sha}
src-git routing https://github.com/openwrt/routing.git^${r_sha}
EOF
}

cmd_write() {
  need_cmd gh
  local opt_p="" opt_l="" opt_r=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --packages) opt_p="${2:-}"; shift 2 ;;
      --luci)     opt_l="${2:-}"; shift 2 ;;
      --routing)  opt_r="${2:-}"; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done

  local p_sha l_sha r_sha p_date l_date r_date p_subj l_subj r_subj
  if [[ -n "$opt_p" ]]; then
    p_sha="$(expand_sha "$PACKAGES_REPO" "$opt_p")"
    IFS=$'\t' read -r _ p_date p_subj <<<"$(resolve_head "$PACKAGES_REPO" "$p_sha")"
  else
    IFS=$'\t' read -r p_sha p_date p_subj <<<"$(resolve_head "$PACKAGES_REPO" "$PACKAGES_REF")"
  fi
  if [[ -n "$opt_l" ]]; then
    l_sha="$(expand_sha "$LUCI_REPO" "$opt_l")"
    IFS=$'\t' read -r _ l_date l_subj <<<"$(resolve_head "$LUCI_REPO" "$l_sha")"
  else
    IFS=$'\t' read -r l_sha l_date l_subj <<<"$(resolve_head "$LUCI_REPO" "$LUCI_REF")"
  fi
  if [[ -n "$opt_r" ]]; then
    r_sha="$(expand_sha "$ROUTING_REPO" "$opt_r")"
    IFS=$'\t' read -r _ r_date r_subj <<<"$(resolve_head "$ROUTING_REPO" "$r_sha")"
  else
    IFS=$'\t' read -r r_sha r_date r_subj <<<"$(resolve_head "$ROUTING_REPO" "$ROUTING_REF")"
  fi

  local synced_at
  synced_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_feeds_conf "$p_sha" "$l_sha" "$r_sha" "$synced_at"

  echo "wrote $FEEDS_CONF"
  echo "  packages ${p_sha:0:12}  ${p_date}  ${p_subj}"
  echo "  luci     ${l_sha:0:12}  ${l_date}  ${l_subj}"
  echo "  routing  ${r_sha:0:12}  ${r_date}  ${r_subj}"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \?//'
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    check)      cmd_status "$@" ;;
    write)      cmd_write "$@" ;;
    print-json) cmd_print_json "$@" ;;
    -h|--help|help|"") usage; [[ -n "$cmd" ]] || exit 1 ;;
    *) die "未知子命令：$cmd（check|write|print-json）" ;;
  esac
}

main "$@"

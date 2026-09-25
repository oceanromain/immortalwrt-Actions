# 版本管理与回退

本仓库用 **Git 标签 + 第三方源固定 commit** 双保险管理版本，目标是随时能一键回退到任一已验证版本，且不再因上游漂移导致补丁失配。

## 版本标签

每个测试过的版本都有一个语义标签，指向该版本最终的 main commit：

| 标签 | 说明 | 对应构建 |
|---|---|---|
| `v5` | 默认 192.168.10.1 / StarNetWrt / conntrack 165535；含 netwizard | run 35189888032 ✅ |
| `v6` | 移除 netwizard，多网卡 DSA 网桥可用（稳定基线） | run 35392813110 ✅ |
| `v7` | 新增 wificalling-location-gateway（WLOC） | run 35543094764 ✅ |
| `v8` | 修复 WLOC mobileconfig 403 | run 35551939484 ✅ |
| `v9` | 移除 WLOC 回 v6 基线；启用 nlbwmon；pushbot 流量走 wrtbwmon | run 35661784360 ✅ |

查看所有版本：
```bash
git fetch --tags
git tag -l "v*"
git show v9 --stat          # 查看某版本内容
```

## 回退到某个版本（推荐方式，保留历史）

不需要 force-push，用一个“回退提交”把 main 的文件还原到目标版本：

```bash
git clone https://github.com/oceanromain/immortalwrt-Actions.git
cd immortalwrt-Actions
git fetch --tags

# 把工作区还原到 v6（文件级还原）
git restore --source=v6 --staged --worktree :/
git clean -fd               # 清除该版本之后新增的未跟踪文件（先 git status 确认）

git commit -m "rollback: restore main to v6 baseline"
git push origin main
```

推送后到 Actions → **ImmortalWrt Builder** → Run workflow 手动触发即可
（本工作流仅 `workflow_dispatch`，push 不会自动编译）。

### 快速方式（移动分支指针，会改写远端历史）

单人仓库、确认无他人协作时可用：
```bash
git reset --hard v6
git push -f origin main
```

## 官方 feed 固定 commit

`feeds.conf.default` 使用 OpenWrt feeds 原生的 `URL^commit` 语法固定官方 feed。2026-09-25 验证 `luci-app-homeproxy` 时锁定：

```bash
packages=6d68ffeb270860be5d73ee2898d58e7c6019d9a4
luci=adc898b447eb4ee8023398182f5d0de2e8817e81
routing=4b9891b9136259f93294a424507ed24c5e8c1cbd
```

对应验证结果：`luci-app-homeproxy=y`，自动拉入 `sing-box 1.12.25`、`firewall4`、`kmod-nft-tproxy`、`ucode-mod-digest`，中文翻译包 `luci-i18n-homeproxy-zh-cn=y`；两轮 `make defconfig` 幂等。

## 第三方源固定 commit

`diy-part1.sh` 顶部集中声明六个第三方源锁定的 commit SHA：

```bash
LUCKY_SHA=...
PUSHBOT_SHA=...
TCPDUMP_SHA=...
ZABBIX_SHA=...
TURBOACC_SHA=...
WRTBWMON_SHA=...
```

构建时每个源都精确检出到对应 SHA；对不上立即中止构建。
**这是 v9 第一次失败（anchor count=0）的根治措施**——此前 `--depth 1` 拉的是上游最新 master，上游一旦改写代码，diy2 的补丁就会失配。

### 升级某个第三方源

1. 修改 `diy-part1.sh` 里对应的 `*_SHA`（新 commit 需先在上游确认）
2. 本地完整验证：
   ```bash
   bash diy-part1.sh
   bash diy-part2.sh           # 若 diy2 对该源有补丁，确认仍命中
   ```
3. 提交推送，手动触发编译
4. 验证通过后，给新版本补一个标签：
   ```bash
   git tag -a v10 -m "v10: <本版说明>"
   git push origin v10
   ```

## 新版本发布检查清单

- [ ] 本地两轮 `make defconfig` 幂等
- [ ] `bash diy-part1.sh && bash diy-part2.sh` 沙盒通过
- [ ] 手动触发 Actions，确认第 8 步 Load custom configuration 变绿
- [ ] 固件实机测试通过
- [ ] 打新标签并推送
- [ ] 更新本文件的版本表与 README（如需）

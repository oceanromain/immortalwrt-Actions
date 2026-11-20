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

## 官方 feed 固定 commit（钉死 + 跟随）

`feeds.conf.default` 使用 OpenWrt 原生 `URL^commit`：**每次构建可复现**，同时用同步机制**跟随上游 tip**，避免 core 狂奔、feed 冬眠。

### 策略

| 层 | 策略 | 谁来动 |
|---|---|---|
| immortalwrt **core** | `master` 浮动；成功构建写入 `.last-immortalwrt-build-sha` | `upstream-check.yml`（周一 15:00 北京） |
| **packages / luci / routing** | 始终 `src-git …^<sha>` 钉死；定期对齐 tip | `feed-sync.yml` + `scripts/sync-feed-pins.sh` |
| 第三方 community | `diy-part1.sh` 的 `*_SHA` | 人工改 SHA（补丁锚点敏感，不自动跟） |

原则：**构建消费的永远是 pin，不是裸 tip**；「新」来自主动 bump pin，「稳」来自 pin 不变则字节级可复现。

### 当前 pin

以仓库根 `feeds.conf.default` 为准（文件头注释含 Last synced）。历史锚点：

- 2026-09-25（homeproxy 验证基线）：
  `packages=6d68ffeb…` / `luci=adc898b4…` / `routing=4b9891b9…`
  → `luci-app-homeproxy=y`，拉入 `sing-box` / `firewall4` / `kmod-nft-tproxy` 等；两轮 `make defconfig` 幂等。
- 2026-11-20：引入 `scripts/sync-feed-pins.sh` + `Feed Pin Sync` 工作流，pin 对齐当时 upstream tip（packages 已含 rust 1.96.1，`patches/060` 将 no-op）。

### 如何跟随上游（日常）

**推荐：PR 模式（默认）**

1. Actions → **Feed Pin Sync** → Run workflow → `mode=pr`  
   （定时：每周一 16:00 北京，有漂移则 force-push 分支 `chore/feed-pins-auto` 并开/更新 PR）
2. 审 PR 里的 packages/luci/routing 短 SHA → 合并 main
3. Actions → **ImmortalWrt Builder** → Run workflow
4. 全绿 + 实机冒烟后，可选打 `vN` 标签

**本地一手办：**

```bash
# 看是否落后 tip（落后 exit 2）
bash scripts/sync-feed-pins.sh check

# 对齐到当前 tip 并写回 feeds.conf.default
bash scripts/sync-feed-pins.sh write

# 或钉到指定 commit（回退/对齐某次已知好版本）
bash scripts/sync-feed-pins.sh write \
  --packages 6d68ffeb270860be5d73ee2898d58e7c6019d9a4 \
  --luci adc898b447eb4ee8023398182f5d0de2e8817e81 \
  --routing 4b9891b9136259f93294a424507ed24c5e8c1cbd
```

**激进：直接写 main（单人仓可用）**

Feed Pin Sync → `mode=main`，可选勾选 `open_builder` 自动触发编译。失败时用下面回退 pin。

### feed bump 后检查清单

- [ ] `Load custom configuration` 绿（`patches/*.sh` 锚点仍命中或按设计 no-op）
- [ ] `make defconfig` / 编译全绿；`*.manifest` 关注包版本（homeproxy / sing-box / rust 等）
- [ ] 若某定点补丁在新 tip 上锚点失败：先修 `patches/` 再重编，不要改回裸 tip
- [ ] 实机冒烟；通过后更新本文件「当前 pin」叙述并可选打标签

### 只回退官方 feed pin

```bash
git restore --source=<已知好 commit> -- feeds.conf.default
git commit -m "rollback: feeds pins to <desc>"
git push
# 再手动 Run ImmortalWrt Builder
```

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

### PushBot 升级记录

- 2026-09-26：`c92ce9e4aefb19409ad2c2f9c5e83466a76f44af`（manifest 实测 `5.18-r17`）→ `252ce5558cdc3d8814450329a83c396a6110e512`（`Makefile` 实测 `6.00-r29`）。
- 触发时上游尚未发布/打 `r29` tag，因此以锁定 commit 和 `Makefile` 的 `PKG_VERSION/PKG_RELEASE` 为准。
- 本仓 `diy-part2.sh` 的 wrtbwmon 优先补丁锚点仍唯一命中；两轮 `make defconfig` 幂等。

### Zabbix Agent LuCI 兼容修复

- 2026-09-30：继续锁定 `zzxym/luci-app-zabbix-agent` commit `2a01e4c4a5fe3f92879f1ff3dff0780dc0821b47`，包版本仍为 `1.0.0-r1`。
- 上游原插件使用已废弃的 `htdocs/luci-static/resources/menu.d` 菜单路径，且 UCI 名写成 `zabbix-agentd`；当前 ImmortalWrt 官方后端使用 `zabbix_agentd`，导致固件中有包但 LuCI 不显示。
- `diy-part2.sh` 在构建期完成兼容修复：现代 `root/usr/share/luci/menu.d` 菜单、对应 ACL、重写视图、中文翻译、`zabbix-agentd-sync` 配置同步服务、首启 UCI 默认值。
- 隔离源码树验证通过：两轮 `make defconfig` 幂等；`luci-app-zabbix-agent`、中文翻译、`zabbix-agentd` 符号均保留。

### diy-part2 拆分重构（2026-10-01）

- 原单文件 `diy-part2.sh`（437 行，大部分为内嵌 heredoc）拆为三部分：
  - `files/`：rootfs 覆盖，改用 P3TERX 模板原生 `[ -e files ] && mv files openwrt/files` 机制
  - `custom/<包名>/`：第三方包源码覆盖层，目录名与包名 1:1 对应
  - `patches/*.sh`：动态补丁，按文件名序执行，各带锚点/结果校验
- `diy-part2.sh` 仅保留约 40 行编排逻辑；重构前后构建产物经隔离源码树逐文件比对，字节一致。
- 回退方法：单文件版本完整保留在分支 `backup/diy2-monolith-v11`（= v11 提交 `601f4cb`）。恢复时 `git restore --source=backup/diy2-monolith-v11 -- diy-part2.sh`，并删除 `files/ custom/ patches/` 后提交。

## 新版本发布检查清单

- [ ] 本地两轮 `make defconfig` 幂等
- [ ] `bash diy-part1.sh && bash diy-part2.sh` 沙盒通过
- [ ] 手动触发 Actions，确认第 8 步 Load custom configuration 变绿
- [ ] 固件实机测试通过
- [ ] 打新标签并推送
- [ ] 更新本文件的版本表与 README（如需）

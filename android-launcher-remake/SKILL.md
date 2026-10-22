---
name: android-launcher-remake
description: 把安卓智能电视/投影仪改造为简洁的 Apple TV 风格桌面（Projectivy Launcher），去除预装广告/推送/商店类应用，保留核心系统与用户应用，全程可逆。适用于用户想把安卓TV或智能投影仪（极米/坚果/当贝等）换成干净无广告的桌面、停用预装垃圾应用、摆脱会员推广位的场景。触发词包括“改造电视/投影仪”“换Apple TV风格桌面”“去除电视广告”“刷机后想用简洁桌面”“停用预装应用”等。涉及adb调试、局域网探测、APK安装、系统应用停用、默认launcher设置。
---

# 安卓智能电视 / 投影仪 → Apple TV 风格简洁桌面

把一台安卓智能电视或投影仪，改造成无广告、简洁、可自定义的桌面（基于开源的 **Projectivy Launcher**）。整个流程**全程可逆**（停用而非删除，随时可恢复），并已封装成可复用的脚本。

## 使用时机
用户想给安卓TV / 智能投影仪：
- 去掉开机广告、推荐位、预装垃圾应用
- 换成 Apple TV 风格的简洁桌面（默认 launcher）
- 摆脱自带系统的会员推广 / 内容推荐

## 安全与边界（最高优先级）
1. **只停用，不删除**：所有清理一律用 `pm disable-user --user 0`（可逆），绝不用 `pm uninstall` 删系统应用。
2. **绝不动这些系统核心**：`*launcher`（原桌面，改默认前保留）、`*projectorservice` / `*projection*`（投影核心）、`com.android.*`（系统设置/基础组件）、`com.mediatek.*`（SoC 组件，TV 芯片）、`com.android.tv.settings`。
3. 改默认桌面 / 停用原桌面是**黑屏风险开关**：必须先把新 launcher 装好并确认能进主界面，才可停用原桌面。
4. 全程记录原应用备份，可一键恢复。
5. 这是**修改用户自有设备的系统**：仅停用应用 / 换桌面属于合法操作；**不要**引导任何破解 DRM / 盗链 / 非法聚合影视的用途（用户如想免费看会员内容，只提供合法渠道：Kodi+本地/NAS 片源、官方免费专区、手机会员投屏）。

## 前置条件
- 设备是**安卓系统**（智能电视 / 智能投影仪），能开启「开发者模式 + USB 调试 / ADB 网络调试」。
- 设备与电脑（Mac/Linux）连**同一局域网**。
- 电脑有可用的 adb（脚本会自动探测，找不到会尝试常见安装路径）。
- 若设备未开启 ADB：需先在设备「设置 → 关于 → 连点版本号 7 次 → 开发者选项 → USB 调试 + ADB 网络调试」开启。

## 工作流（按序执行，每步用对应脚本）
| 步骤 | 做什么 | 脚本 |
|---|---|---|
| 1 | **探测**：定位 adb → 扫描局域网找设备(5555) → 连接 → 读系统属性(芯片/安卓版本/TV/桌面) → 检查 root → 列出全部应用 | `scripts/probe_and_backup.sh` |
| 2 | **备份**：把所有第三方应用 APK 备份到本地 | 同上（内置） |
| 3 | **判断可改造性**：确认是安卓系统、可 ADB、拿到 root 或至少可停用户应用；识别广告/推送/商店类目标与必须保留项 | — |
| 4 | **下载安装 launcher**：从 GitHub 官方下载 Projectivy APK（注意网络截断→断点续传+校验zip），adb install | `scripts/setup_launcher.sh` |
| 5 | **设为默认桌面**：授予通知监听+无障碍权限 → 走引导（若引导循环/弹选择器→停用原桌面使其成为唯一HOME）→ 确认进入主界面 | `scripts/setup_launcher.sh` |
| 6 | **清理**：冻结广告/推送/商店类应用（按用户确认的清单） | `scripts/disable_adware.sh` |
| 7 | **验证**：默认 HOME = 新 launcher、前台主界面、目标应用已停用；建议用户重启验证开机直达 | — |
| 8 | **恢复（可选）**：启用被停应用、恢复备份 | `scripts/restore.sh` |

## 关键经验（踩过的坑）
- **adb 常不在 PATH**：brew cask 安装后在 `/usr/local/Caskroom/android-platform-tools/*/platform-tools/adb` 或 `/opt/homebrew/...`，脚本会自动定位。
- **GitHub 大文件下载易截断**：`adb install` 报 `INSTALL_PARSE_FAILED_NOT_APK` 多半是 APK 没下完整；必须对比官方 asset size（`unzip -t` 校验 zip），用 `curl -C -` 断点续传补齐。
- **引导反复回欢迎页**：根因是「系统默认桌面没定」+「通知访问权限弹窗强制跳设置页」。解法：(a) 停用原桌面让新 launcher 成为唯一 HOME；(b) 用 `settings put secure` 直接授予通知监听/无障碍权限消除弹窗；(c) 用 uiautomator dump + input keyevent 走完引导到主界面。
- **设默认桌面顺序**：先装好并验证新 launcher 能进主界面 → 再停用原桌面。
- **芯片判断**：`ro.product.cpu.abi`（常见 `armeabi-v7a`）、`ro.build.characteristics=tv`、`ro.build.version.sdk`（安卓版本）。低配（1G 内存）也够跑 Projectivy。
- **包名差异**：Projectivy 官方 xda 版包名是 `com.spocky.projengmenu`，标准版是 `com.projectivy.launcher`；脚本以实测解析的包名为准。

## 文件清单
- `SKILL.md` — 本文档
- `scripts/probe_and_backup.sh` — 探测 + 备份
- `scripts/setup_launcher.sh` — 下载安装 + 设默认桌面 + 走引导
- `scripts/disable_adware.sh` — 冻结广告/推送/商店应用
- `scripts/restore.sh` — 恢复与回滚
- `references/troubleshooting.md` — 常见问题排查详表

脚本内的设备 IP、要停用的应用清单、要保留的应用，**执行时以探测结果和用户确认为准**，不要硬编码。

## 使用建议
- 对品牌差异、具体机型适配、权限弹窗变化等，先读 `references/troubleshooting.md`。
- 每步执行后都要通过不同于生成路径的方式回读验证（如 `dumpsys`、`resolve-activity`、`uiautomator` dump），确认生效再继续。

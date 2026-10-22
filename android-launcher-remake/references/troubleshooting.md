# 安卓电视/投影 改造常见问题排查

配合 SKILL.md 使用。按“现象 → 原因 → 解法”组织。

## 1. 连不上设备 / ADB 问题
| 现象 | 原因 | 解法 |
|---|---|---|
| 找不到 adb | 未安装或不在 PATH | `brew install android-platform-tools`；cask 装在 `/usr/local/Caskroom/android-platform-tools/*/platform-tools/adb` |
| `unauthorized` | 设备未确认 RSA 授权 | 在设备屏幕上弹窗点「允许 USB 调试」；多设备时对 IP 单独授权 |
| `offline` | 连接中断 / 系统重启 | `adb disconnect` 后重连；重启设备后重连 |
| `connect: 无法访问` | 设备未开 ADB 网络调试 / 不同网段 | 设备「开发者选项」开 USB+ADB 网络调试；确认同一 WiFi |

## 2. 局域网扫描不到设备
- 确认设备已开「ADB 网络调试」，且与电脑**同一网段**（不同 VLAN/访客网络会隔开）。
- 投影仪/电视常见在 `192.168.x.x`，若电脑在别网段，手动指定 IP 更快：`./probe_and_backup.sh 192.168.x.x`。
- 若只知道型号不知道 IP：进路由器后台看连接设备，或设备设置「网络信息」看 IP。

## 3. APK 下载总是不完整
- **现象**：`adb install` 报 `INSTALL_PARSE_FAILED_NOT_APK`，或 `unzip -t` 报 `End-of-central-directory signature not found`。
- **原因**：GitHub 大文件下载被截断（网络/代理）。文件头是 `PK` 但尾部缺失。
- **解法**：断点续传补齐到官方 size——`curl -sL -C - -o file.apk <url>`；用 API 对比 `size` 字段与本地大小；`unzip -t` 校验通过才装。脚本 setup_launcher.sh 已内置多尝试 + 校验。

## 4. 引导反复回到欢迎页（最高频坑）
- **现象**：Projectivy 引导走几步后又跳回第一页“欢迎！”，无法进主界面。
- **根因**（通常同时存在两个）：
  1. **系统默认桌面没定**：新 launcher 与原桌面并存，系统不知道该用哪个 → `resolve-activity HOME` 返回 `ResolverActivity`（选择器）。
  2. **通知访问权限弹窗强制跳系统设置页**：点“确定”会跳到 `tv.settings/device.apps`，返回时引导被重置。
- **解法**：
  1. 停用原自带桌面 → 新 launcher 成为唯一 HOME（`pm disable-user --user 0 <原launcher>`）。
  2. 用 `settings put secure` 直接授予通知监听 + 无障碍，消除弹窗：
     ```
     settings put secure enabled_notification_listeners "<pkg>/.services.notification.NotificationListener"
     settings put secure enabled_accessibility_services "<pkg>/.services.ProjectivyAccessibilityService"
     settings put secure accessibility_enabled 1
     ```
  3. 用 `uiautomator dump` + `input keyevent` 走完引导：弹窗选“否”避免跳设置页，其余按确认，直到前台是主界面。
- 判定成功：`resolve-activity HOME` 返回 `com.<pkg>/.ui.home.MainActivity`，且前台是 MainActivity 而非 onboarding。

## 5. 设默认桌面后原桌面要不要停
- 不停原桌面 → 按 Home 会弹“选择默认桌面”，需在设备上选一次“始终”。
- 想开机直达新桌面 → 停用原桌面（可逆）。**顺序**：先装好并验证新 launcher 能进主界面 → 再停原桌面，避免黑屏。

## 6. 黑屏/进不去桌面的预防与自救
- 不要删除原桌面，只停用；保留其 APK 备份。
- 若停用原桌面后黑屏：`pm enable <原launcher>` 立即恢复。
- 改前先备份 `packages.xml`（系统默认记录）。

## 7. 品牌 / 机型差异
- **芯片**：联发科 MT5862/MT8168 等常见于投影（`ro.build.characteristics=tv`）；`ro.product.cpu.abi` 多为 `armeabi-v7a`。低配 1G 内存也够跑 Projectivy。
- **桌面包名**：不同品牌不同（如坚果/当贝常为 `com.siviton.projector.launcher`）。以 `resolve-activity HOME` 实测为准，不要硬编码。
- **预装广告应用**：常见关键词 `pushserver`（广告推送源）、`appstore`/`dbappstore`（应用商店）、`market`/`androidbox`、`dianshijia`（电视家直播）等。以 `pm list packages -s` 实测匹配。
- **协议封闭系统**（三星 Tizen、LG webOS、部分 TCL 定制）不是安卓，本流程不适用。

## 8. 合法合规边界（必须遵守）
- 本 Skill 只做：换桌面、停用预装应用、装开源 launcher、播放本地/NAS 片源（Kodi）。这些是修改自有设备系统，属合规操作。
- **严禁**：破解视频平台 DRM、盗链聚合影视、逆向会员校验、传播破解方法。用户想看平台会员内容，只给合法途径：官方正版 APP + 会员、手机/平板会员投屏、官方免费专区、Kodi 播放本地自有片源。

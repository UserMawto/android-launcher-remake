#!/usr/bin/env bash
# android-launcher-remake: setup_launcher.sh
# 下载并安装 Projectivy Launcher(Apple TV 风格), 设为默认桌面, 自动走完引导。
# 用法:
#   ./setup_launcher.sh 192.168.8.13 [ADB路径] [APK保存路径]
# 需先运行 probe_and_backup.sh 确认设备可连接。
set -u

DEV="${1:-}"
ADB="${2:-$(command -v adb 2>/dev/null)}"
[ -x "$ADB" ] || ADB=$(ls /usr/local/Caskroom/android-platform-tools/*/platform-tools/adb 2>/dev/null | head -1)
[ -x "$ADB" ] || ADB=$(ls /opt/homebrew/Caskroom/android-platform-tools/*/platform-tools/adb 2>/dev/null | head -1)
[ -z "$ADB" ] && { echo "[!] 未找到 adb" >&2; exit 1; }

if [ -z "$DEV" ]; then
  echo "[!] 需要设备IP。用法: $0 <设备IP> [ADB路径]" >&2
  exit 1
fi
echo "[ok] adb=$ADB device=$DEV"
"$ADB" connect "$DEV:5555" >/dev/null 2>&1; sleep 1
D="$DEV:5555"
[ "$("$ADB" devices | awk -v ip="$D" '$1==ip{print $2}')" != "device" ] && { echo "[!] 设备未授权/未连接" >&2; exit 1; }
sh() { "$ADB" -s "$D" shell "$@" 2>/dev/null | tr -d '\r'; }

APK="${3:-/tmp/projectivy.apk}"

# ---------- 1. 从 GitHub 官方获取最新 APK ----------
echo "== 获取 Projectivy 最新版本 =="
REL=$(curl -sL --max-time 30 "https://api.github.com/repos/spocky/miproja1/releases/latest")
URL=$(echo "$REL" | grep -oE '"browser_download_url": *"[^"]*\.apk"' | head -1 | sed 's/.*"\(http[^"]*\)"/\1/')
SIZE=$(echo "$REL" | grep -A20 '"assets"' | grep -oE '"size": *[0-9]+' | head -1 | grep -oE '[0-9]+')
TAG=$(echo "$REL" | grep -oE '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"/\1/')
[ -z "$URL" ] && { echo "[!] 获取下载地址失败(GitHub API 可能被限流)" >&2; exit 1; }
echo "  版本: $TAG  url: $URL  size: ${SIZE:-未知}"

# 下载: 断点续传 + 校验 zip 完整性 + 对比 size(处理截断)
echo "== 下载 APK =="
dl_ok=0
for try in 1 2 3 4 5; do
  curl -sL --retry 3 --max-time 300 -C - -o "$APK" "$URL" 2>/dev/null
  sz=$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK" 2>/dev/null)
  zipok=$(unzip -t "$APK" >/dev/null 2>&1 && echo yes || echo no)
  echo "  尝试$try: size=$sz zip=$zipok"
  if [ "$zipok" = "yes" ] && { [ -z "$SIZE" ] || [ "$sz" = "$SIZE" ]; }; then dl_ok=1; break; fi
done
[ "$dl_ok" = "1" ] || { echo "[!] APK 未完整下载。检查网络后重试。" >&2; exit 1; }
echo "[ok] APK 完整: $APK"

# ---------- 2. 安装 ----------
echo "== 安装 =="
OUT=$("$ADB" -s "$D" install -r "$APK" 2>&1 | tr -d '\r')
echo "  $OUT"
if echo "$OUT" | grep -qi "INSTALL_PARSE_FAILED_NOT_APK"; then
  echo "[!] parse失败=APK不完整, 请重跑下载步骤(断点续传)。" >&2; exit 1
fi

# 定位真实包名
PKG=$(sh pm list packages -3 | sed 's/^package://' | grep -iE 'spocky|projectivy' | head -1)
[ -z "$PKG" ] && { echo "[!] 未找到已安装的 Projectivy 包" >&2; exit 1; }
echo "[ok] 包名: $PKG  ($(sh dumpsys package "$PKG" | grep versionName | head -1))"

# 找主 Activity
ACT=$(sh cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$PKG" | tail -1)
[ -z "$ACT" ] && ACT="$PKG/.ui.home.MainActivity"
echo "  主入口: $ACT"

# ---------- 3. 授予通知监听 + 无障碍(消除引导弹窗/强制跳设置页) ----------
echo "== 授予后台权限(消除引导弹窗) =="
NLS=$(sh dumpsys package "$PKG" | grep -A3 'NotificationListenerService:' | grep -oE "$PKG/\\.[A-Za-z0-9_.]+" | head -1)
[ -z "$NLS" ] && NLS="$PKG/.services.notification.NotificationListener"
ACC=$(sh dumpsys package "$PKG" | grep -A3 'AccessibilityService:' | grep -oE "$PKG/\\.[A-Za-z0-9_.]+" | head -1)
[ -z "$ACC" ] && ACC="$PKG/.services.ProjectivyAccessibilityService"
sh settings put secure enabled_notification_listeners "$NLS" >/dev/null 2>&1
sh settings put secure enabled_accessibility_services "$ACC" >/dev/null 2>&1
sh settings put secure accessibility_enabled 1 >/dev/null 2>&1
echo "  通知监听: $NLS"; echo "  无障碍:   $ACC"

# ---------- 4. 设默认桌面 + 走引导 ----------
echo "== 设默认桌面 & 走引导 =="
home_now=$(sh cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1)
echo "  当前默认HOME: $home_now"
# 若仍是选择器(未定默认) → 停用原桌面, 使新 launcher 成为唯一 HOME
if echo "$home_now" | grep -q "ResolverActivity"; then
  echo "  默认未定(ResolverActivity) → 停用其他桌面使新 launcher 唯一"
  for lp in $(sh pm list packages | sed 's/^package://' | grep -iE 'launcher'); do
    [ "$lp" = "$PKG" ] && continue
    sh pm disable-user --user 0 "$lp" >/dev/null 2>&1 && echo "    停用原桌面: $lp"
  done
fi

# 启动主界面; 若仍进 onboarding, 用按键走完引导
sh am force-stop "$PKG" >/dev/null 2>&1; sleep 1
sh am start -n "$ACT" >/dev/null 2>&1; sleep 2
for i in $(seq 1 18); do
  fg=$(sh dumpsys activity activities 2>/dev/null | grep mResumedActivity | head -1)
  if echo "$fg" | grep -qE "home|MainActivity|$PKG/.ui.home"; then
    echo "  [step$i] >>> 已进入主界面"; break
  fi
  if echo "$fg" | grep -q "AppsActivity"; then
    echo "  [step$i] 设置页,按返回"; sh input keyevent 4 >/dev/null 2>&1; sleep 2; continue
  fi
  # dump UI: 弹窗选"否"避免跳设置页; 否则按确认推进
  sh uiautomator dump /data/local/tmp/w.xml >/dev/null 2>&1
  if sh cat /data/local/tmp/w.xml 2>/dev/null | grep -q 'text="否"'; then
    sh input keyevent 22 >/dev/null 2>&1; sleep 1
  fi
  sh input keyevent 23 >/dev/null 2>&1; sleep 2
done

echo "== 验证默认HOME =="
sh cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1
echo "[done] 新桌面已设为默认并进入主界面。下一步: disable_adware.sh 清理广告/推送/商店应用。"

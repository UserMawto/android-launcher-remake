#!/usr/bin/env bash
# android-launcher-remake: disable_adware.sh
# 冻结(停用,可逆)广告/推送/商店类应用, 绝不删除。
# 用法:
#   ./disable_adware.sh <设备IP>                    # 按内置关键词自动匹配冻结
#   ./disable_adware.sh <设备IP> pkg1 pkg2 ...      # 显式冻结指定包(推荐)
# 安全: 只 pm disable-user(可恢复), 不碰 launcher/projector 核心/com.android 基础。
set -u

DEV="${1:-}"
[ -z "$DEV" ] && { echo "[!] 用法: $0 <设备IP> [包名...]" >&2; exit 1; }
ADB=$(command -v adb 2>/dev/null)
[ -x "$ADB" ] || ADB=$(ls /usr/local/Caskroom/android-platform-tools/*/platform-tools/adb 2>/dev/null | head -1)
[ -x "$ADB" ] || ADB=$(ls /opt/homebrew/Caskroom/android-platform-tools/*/platform-tools/adb 2>/dev/null | head -1)
"$ADB" connect "$DEV:5555" >/dev/null 2>&1; sleep 1
D="$DEV:5555"
sh() { "$ADB" -s "$D" shell "$@" 2>/dev/null | tr -d '\r'; }

# 绝对不冻结的保护名单
PROTECT=$(sh pm list packages | sed 's/^package://' | grep -iE 'launcher|projector|projection|tv\.settings|^android$|com\.android\.tv\.settings')

if [ $# -gt 1 ]; then
  TARGETS="${@:2}"
else
  echo "== 未指定包, 按关键词自动识别广告/推送/商店 =="
  TARGETS=$(sh pm list packages -s | sed 's/^package://' \
    | grep -iE 'pushserver|appstore|dbappstore|market|androidbox|siviton\.push|\.ad\.|advert|medusa|browser' || true)
  [ -z "$TARGETS" ] && { echo "  未自动匹配到目标, 请显式传入包名。" ; exit 0; }
fi

echo "== 目标待冻结 =="
for p in $TARGETS; do
  echo "$PROTECT" | grep -qx "$p" && { echo "  [skip] $p (保护名单,跳过)"; continue; }
  out=$(sh pm disable-user --user 0 "$p" 2>&1 | tr -d '\r')
  if echo "$out" | grep -qi "new state: disabled"; then
    echo "  [disabled] $p"
  else
    echo "  [fail] $p: $out"
  fi
done

echo "[done] 冻结完成(全部可逆, 用 restore.sh 或 pm enable 恢复)。"

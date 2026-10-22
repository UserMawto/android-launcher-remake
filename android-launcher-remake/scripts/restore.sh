#!/usr/bin/env bash
# android-launcher-remake: restore.sh
# 恢复: 启用所有被停用(disabled-user)的应用, 并按需还原默认桌面。
# 用法:
#   ./restore.sh <设备IP>                 # 启用所有被停用的应用(含原桌面/推送)
#   ./restore.sh <设备IP> pkg1 pkg2 ...   # 只启用指定包
# 说明: 停用是可逆的(disabled-user), 本脚本将其 pm enable 恢复; 不删除任何数据。
set -u

DEV="${1:-}"
[ -z "$DEV" ] && { echo "[!] 用法: $0 <设备IP> [包名...]" >&2; exit 1; }
ADB=$(command -v adb 2>/dev/null)
[ -x "$ADB" ] || ADB=$(ls /usr/local/Caskroom/android-platform-tools/*/platform-tools/adb 2>/dev/null | head -1)
[ -x "$ADB" ] || ADB=$(ls /opt/homebrew/Caskroom/android-platform-tools/*/platform-tools/adb 2>/dev/null | head -1)
"$ADB" connect "$DEV:5555" >/dev/null 2>&1; sleep 1
D="$DEV:5555"
sh() { "$ADB" -s "$D" shell "$@" 2>/dev/null | tr -d '\r'; }

if [ $# -gt 1 ]; then
  TARGETS="${@:2}"
else
  echo "== 查找所有被停用的应用 =="
  # dumpsys 里 enabled=3 表示 disabled-user
  TARGETS=$(sh dumpsys package 2>/dev/null | grep -B2 "enabled=3" | grep -oE "Package \\[com\\.[a-zA-Z0-9_.]+\\]" | sed -E 's/Package \\[([^]]+)\\]/\1/' | sort -u)
  [ -z "$TARGETS" ] && { echo "  未发现被停用的应用(已全部正常)。"; exit 0; }
fi

echo "== 恢复(enable) =="
for p in $TARGETS; do
  out=$(sh pm enable "$p" 2>&1 | tr -d '\r')
  echo "  [$p] $out"
done

# 提示: 若此前停用了原桌面, 恢复后默认桌面会回到选择器状态(可再选原桌面或 Projectivy)
echo "[done] 恢复完成。注意: 若恢复了原自带桌面, 开机可能回到"选择默认桌面"弹窗, 在设备上选"始终"即可。"

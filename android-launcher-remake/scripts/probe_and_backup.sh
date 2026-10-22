#!/usr/bin/env bash
# android-launcher-remake: probe_and_backup.sh
# 探测安卓智能电视/投影仪并备份原应用。用法:
#   ./probe_and_backup.sh                 # 自动扫描局域网找设备(5555)
#   ./probe_and_backup.sh 192.168.8.13    # 指定设备IP
# 依赖: bash3+, adb(自动定位), ping/nc(可用), curl
set -u

# ---------- 定位 adb ----------
find_adb() {
  local candidates=(
    "$(command -v adb 2>/dev/null)"
    /usr/local/Caskroom/android-platform-tools/*/platform-tools/adb
    /opt/homebrew/Caskroom/android-platform-tools/*/platform-tools/adb
    /usr/local/bin/adb /opt/homebrew/bin/adb
  )
  for c in "${candidates[@]}"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

ADB=$(find_adb)
if [ -z "$ADB" ]; then
  echo "[!] 未找到 adb。请先安装: brew install android-platform-tools 或下载 platform-tools。" >&2
  echo "    提示: cask 装在 /usr/local/Caskroom/android-platform-tools/*/platform-tools/adb" >&2
  exit 1
fi
echo "[ok] adb = $ADB"
"$ADB" start-server >/dev/null 2>&1

# ---------- 定位设备 ----------
DEV=""
if [ $# -ge 1 ] && [ -n "$1" ]; then
  DEV="$1"
  echo "[use] 指定设备 IP: $DEV"
else
  echo "[..] 自动扫描局域网 5555 端口设备 ..."
  MYIP=$(ipconfig getifaddr en0 2>/dev/null || ifconfig 2>/dev/null | awk '/inet / && $2!="127.0.0.1"{print $2; exit}')
  [ -z "$MYIP" ] && MYIP="192.168.1.1"
  NET=$(echo "$MYIP" | awk -F. '{print $1"."$2"."$3}')
  echo "[..] 网段 $NET.0/24"
  # 并行 ping 让设备填 ARP
  for i in $(seq 1 254); do ( ping -c1 -W1 "$NET.$i" >/dev/null 2>&1 & ); done
  sleep 3
  for i in $(seq 1 254); do
    if nc -z -G1 -w1 "$NET.$i" 5555 2>/dev/null; then
      echo "[+] 发现 ADB 设备: $NET.$i:5555"
      DEV="$NET.$i"
      break
    fi
  done
  [ -z "$DEV" ] && { echo "[!] 未找到开放 5555 端口的设备。请确认设备已开 ADB 网络调试并同网。可手动指定 IP 重试。" >&2; exit 1; }
fi

"$ADB" connect "$DEV:5555" >/dev/null 2>&1
sleep 1
STATE=$("$ADB" devices | awk -v ip="$DEV:5555" '$1==ip{print $2}')
if [ "$STATE" != "device" ]; then
  echo "[!] 设备 $DEV 未就绪(状态=$STATE)。若为 unauthorized: 需在设备屏幕上确认 RSA 授权。若 offline: 重连。" >&2
  exit 1
fi
echo "[ok] 已连接 $DEV (authorized/device)"

D="$DEV:5555"
sh() { "$ADB" -s "$D" shell "$@" 2>/dev/null | tr -d '\r'; }

# ---------- 读系统配置 ----------
echo "== 系统配置 =="
echo "  Android:   $(sh getprop ro.build.version.release) (sdk $(sh getprop ro.build.version.sdk))"
echo "  品牌/型号: $(sh getprop ro.product.brand) / $(sh getprop ro.product.model) ($(sh getprop ro.product.manufacturer))"
echo "  芯片架构:  $(sh getprop ro.product.cpu.abi)"
echo "  系统类型:  $(sh getprop ro.build.characteristics)   (tv = 电视/投影)"
echo "  当前桌面:  $(sh cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1)"
echo "  Root:      $(sh id | grep -q 'uid=0' && echo 'YES (可停用系统应用)' || echo 'NO (仅可停用户应用)')"

# ---------- 应用清单 ----------
echo "== 第三方/用户应用(可直接停用/备份) =="
sh pm list packages -3 | sed 's/^package://'
echo "== 系统预装(节选: 桌面/推送/商店/浏览器/语音/向导) =="
sh pm list packages -s | sed 's/^package://' | grep -iE 'launcher|push|store|appstore|market|browser|tvui|setupwizard|androidbox|siviton|mediatek.wwtv.setupwizard|dianshijia' || echo "  (无匹配或命令受限)"

# ---------- 备份第三方应用 ----------
echo "== 备份第三方应用 =="
BK="${2:-./backup_apks}"
mkdir -p "$BK"
count=0
for p in $(sh pm list packages -3 | sed 's/^package://'); do
  path=$(sh pm path "$p" | grep '^package:' | sed 's/^package://' | head -1)
  [ -z "$path" ] && continue
  if "$ADB" -s "$D" pull "$path" "$BK/$p.apk" >/dev/null 2>&1; then
    echo "  [backup] $p -> $BK/$p.apk"; count=$((count+1))
  fi
done
echo "[ok] 备份完成: $count 个应用 -> $BK"
echo "[done] 探测完成。下一步参考 SKILL.md 流程 4(setup_launcher.sh)。"

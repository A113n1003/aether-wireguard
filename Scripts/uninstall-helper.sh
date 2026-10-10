#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ "$EUID" == 0 ]] || { echo "卸载后台服务需要管理员权限。" >&2; exit 1; }
[[ "$#" == 0 ]] || { echo "此命令不接受路径或其他参数。" >&2; exit 1; }
label=io.aether.wireguard.service
destination=/Library/PrivilegedHelperTools/io.aether.wireguard
plist=/Library/LaunchDaemons/io.aether.wireguard.service.plist
fail() { echo "$*" >&2; exit 1; }
check_path() {
  local path="$1" type="$2" owner mode actual
  [[ ! -L "$path" ]] || fail "安装路径不安全，拒绝卸载。"
  read -r owner mode actual <<< "$(/usr/bin/stat -f '%u %Lp %HT' "$path")"
  [[ "$owner" == 0 && "$actual" == "$type" ]] && (( (8#$mode & 0022) == 0 )) || fail "安装所有者或权限不符合要求。"
  if /bin/ls -lde "$path" | /usr/bin/grep -Eq '^[[:space:]]*[0-9]+:'; then fail "安装路径包含额外 ACL，拒绝卸载。"; fi
}
no_active_tunnel() {
  local file
  for file in /var/run/aether-*/active.json; do
    [[ ! -e "$file" && ! -L "$file" ]] || fail "请先断开 Aether 隧道，再卸载后台服务。"
  done
  ! /usr/bin/pgrep -x AetherBridge >/dev/null 2>&1 || fail "Aether 后台操作尚未结束，请稍后重试。"
}
for directory in /Library /Library/PrivilegedHelperTools /Library/LaunchDaemons; do check_path "$directory" Directory; done
if [[ ! -e "$destination" && ! -e "$plist" ]]; then echo "Aether 后台服务未安装。"; exit 0; fi
[[ -e "$destination" && -e "$plist" ]] || fail "安装不完整，请先修复安装。"
check_path "$destination" Directory
check_path "$plist" "Regular File"
for file in AetherService AetherBridge policy.json; do check_path "$destination/$file" "Regular File"; done
[[ "$(/usr/bin/plutil -extract Label raw -o - "$plist")" == "$label" ]] || fail "拒绝卸载其他服务。"
[[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$plist")" == "$destination/AetherService" ]] || fail "服务路径不属于 Aether。"
no_active_tunnel
stage="$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.aether-uninstall.XXXXXX)"
was_loaded=0; complete=0; moved_helper=0; moved_plist=0
restore() {
  local status="$?"
  if [[ "$complete" == 0 ]]; then
    if [[ "$moved_helper" == 1 ]]; then
      if /bin/mv "$stage/helper" "$destination"; then moved_helper=0; else echo "后台文件恢复失败，备份保留于：$stage" >&2; fi
    fi
    if [[ "$moved_plist" == 1 ]]; then
      if /bin/mv "$stage/service.plist" "$plist"; then moved_plist=0; else echo "服务注册文件恢复失败，备份保留于：$stage" >&2; fi
    fi
    if [[ "$was_loaded" == 1 ]]; then /bin/launchctl bootstrap system "$plist" >/dev/null 2>&1 || echo "旧版后台服务未恢复运行，请管理员检查。" >&2; fi
  fi
  if [[ "$complete" == 1 || ( "$moved_helper" == 0 && "$moved_plist" == 0 ) ]]; then
    /bin/rm -rf "$stage" || echo "后台服务已卸载，残留备份目录：$stage" >&2
  fi
  exit "$status"
}
trap restore EXIT
if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
  /bin/launchctl bootout "system/$label" >/dev/null 2>&1 || fail "无法停止后台服务。"
  was_loaded=1
fi
no_active_tunnel
/bin/mv "$destination" "$stage/helper"
moved_helper=1
/bin/mv "$plist" "$stage/service.plist"
moved_plist=1
complete=1
echo "Aether 后台服务已卸载；用户配置与其他 VPN 未改动。"

#!/bin/bash
# 一次管理员安装。日常连接只使用经过代码签名校验的 XPC。
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077
fail() { echo "$*" >&2; exit 1; }
[[ "$EUID" == 0 ]] || fail "请通过 Aether 的管理员安装流程运行此脚本。"
[[ "$#" == 3 ]] || fail "用法：install-helper.sh <helper bundle> <用户 UID> <Aether.app>"
source_bundle="$1"
allowed_uid="$2"
client_app="$3"
[[ "$allowed_uid" =~ ^[1-9][0-9]{2,9}$ ]] && [[ "$allowed_uid" -ge 501 && "$allowed_uid" -le 4294967294 ]] || fail "无效的用户 UID。"
[[ -d "$source_bundle" && ! -L "$source_bundle" ]] || fail "安装包不存在或包含符号链接。"
[[ -d "$client_app" && ! -L "$client_app" ]] || fail "客户端不存在或包含符号链接。"
source_bundle="$(cd -P "$source_bundle" && pwd)"
client_app="$(cd -P "$client_app" && pwd)"
label=io.aether.wireguard.service
parent=/Library/PrivilegedHelperTools
destination="$parent/io.aether.wireguard"
plist=/Library/LaunchDaemons/io.aether.wireguard.service.plist

verify_root_path() {
  local path="$1" type="$2" owner mode actual
  [[ ! -L "$path" ]] || fail "安装目录不允许使用符号链接。"
  read -r owner mode actual <<< "$(/usr/bin/stat -f '%u %Lp %HT' "$path")"
  [[ "$owner" == 0 && "$actual" == "$type" ]] && (( (8#$mode & 0022) == 0 )) || fail "安装目录所有者或权限不安全。"
  if /bin/ls -lde "$path" | /usr/bin/grep -Eq '^[[:space:]]*[0-9]+:'; then fail "安装路径含有额外 ACL，拒绝修改。"; fi
}
verify_code() {
  local executable="$1" metadata
  [[ -f "$executable" && ! -L "$executable" ]] || fail "缺少安装可执行文件。"
  /usr/bin/codesign --verify --strict "$executable" >/dev/null 2>&1 || fail "安装可执行文件签名无效。"
  metadata="$(/usr/bin/codesign -d --verbose=4 "$executable" 2>&1)"
  /usr/bin/grep -Eq '^CodeDirectory .*flags=.*\(.*runtime' <<< "$metadata" || fail "安装可执行文件必须启用 Hardened Runtime。"
}
code_hash() {
  /usr/bin/codesign -d --verbose=4 "$1" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p'
}
no_active_tunnel() {
  local file
  for file in /var/run/aether-*/active.json; do
    [[ ! -e "$file" && ! -L "$file" ]] || fail "请先断开 Aether 隧道，再安装或更新后台服务。"
  done
  ! /usr/bin/pgrep -x AetherBridge >/dev/null 2>&1 || fail "Aether 后台操作尚未结束，请稍后重试。"
}

for directory in /Library "$parent" /Library/LaunchDaemons; do
  if [[ ! -e "$directory" ]]; then /bin/mkdir "$directory"; /usr/sbin/chown root:wheel "$directory"; /bin/chmod 755 "$directory"; fi
  verify_root_path "$directory" Directory
done
[[ ! -L "$destination" && ! -L "$plist" ]] || fail "已有安装路径不安全。"
if [[ -e "$destination" ]]; then
  verify_root_path "$destination" Directory
  for name in AetherService AetherBridge policy.json; do verify_root_path "$destination/$name" "Regular File"; done
fi
if [[ -e "$plist" ]]; then
  verify_root_path "$plist" "Regular File"
  [[ "$(/usr/bin/plutil -extract Label raw -o - "$plist")" == "$label" ]] || fail "此路径存在不属于 Aether 的服务。"
fi
no_active_tunnel
/usr/bin/codesign --verify --deep --strict "$client_app" >/dev/null 2>&1 || fail "客户端签名验证失败。"
client_info="$(/usr/bin/codesign -d --verbose=4 "$client_app" 2>&1)"
[[ "$client_info" == *$'\nIdentifier=io.aether.wireguard\n'* ]] || fail "客户端标识不符合要求。"
/usr/bin/grep -Eq '^CodeDirectory .*flags=.*\(.*runtime' <<< "$client_info" || fail "客户端必须启用 Hardened Runtime。"
client_hash="$(code_hash "$client_app")"
[[ "$client_hash" =~ ^[0-9a-f]{40}$ ]] || fail "无法绑定客户端代码签名。"
verify_code "$source_bundle/AetherService"
verify_code "$source_bundle/AetherBridge"
service_hash="$(code_hash "$source_bundle/AetherService")"
bridge_hash="$(code_hash "$source_bundle/AetherBridge")"
[[ "$service_hash" =~ ^[0-9a-f]{40}$ && "$bridge_hash" =~ ^[0-9a-f]{40}$ ]] || fail "安装签名不完整。"
[[ -d "$source_bundle/Tools/bin" && -d "$source_bundle/Tools/lib" && -f "$source_bundle/Tools/tools-manifest.json" ]] || fail "缺少冻结工具链。"
if [[ -n "$(/usr/bin/find "$source_bundle" -type l -print -quit)" || -n "$(/usr/bin/find "$source_bundle" ! -type d ! -type f -print -quit)" ]]; then fail "安装包只允许无符号链接的普通文件。"; fi
manifest_hash="$(/usr/bin/shasum -a 256 "$source_bundle/Tools/tools-manifest.json" | /usr/bin/awk '{print $1}')"

# 所有复制和校验在 root 独占目录中进行；复制后再次校验，避免用户可写源被替换。
stage="$(/usr/bin/mktemp -d "$parent/.aether-install.XXXXXX")"
backup="$stage/previous"
had_plist=0; was_loaded=0; service_stopped=0; replaced=0; success=0
cleanup() {
  local status="$?" rollback_failed=0
  if [[ "$success" == 0 ]]; then
    if [[ "$replaced" == 1 ]]; then
      /bin/launchctl bootout "system/$label" >/dev/null 2>&1 || true
      /bin/rm -rf "$destination" || rollback_failed=1
      if [[ -d "$backup" ]]; then /bin/mv "$backup" "$destination" || rollback_failed=1; fi
      if [[ "$had_plist" == 1 ]]; then
        /bin/cp "$stage/previous.plist" "$plist" || rollback_failed=1
        /bin/chmod 644 "$plist" || rollback_failed=1
      else /bin/rm -f "$plist" || rollback_failed=1
      fi
    fi
    if [[ "$service_stopped" == 1 && "$was_loaded" == 1 ]]; then /bin/launchctl bootstrap system "$plist" >/dev/null 2>&1 || rollback_failed=1; fi
  fi
  if [[ "$rollback_failed" == 0 ]]; then /bin/rm -rf "$stage" || echo "安装备份清理未完成：$stage" >&2
  else echo "自动恢复未完成，管理员可从备份恢复：$stage" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
/bin/mkdir "$stage/new"
for name in AetherService AetherBridge Tools; do /bin/cp -R "$source_bundle/$name" "$stage/new/$name"; done
if [[ -n "$(/usr/bin/find "$stage/new" -type l -print -quit)" ]]; then fail "安装包不允许包含符号链接。"; fi
if [[ -n "$(/usr/bin/find "$stage/new" ! -type d ! -type f -print -quit)" ]]; then fail "安装包包含非普通文件。"; fi
/usr/sbin/chown -R root:wheel "$stage/new"
/bin/chmod -RN "$stage/new"
/usr/bin/find "$stage/new" -type d -exec /bin/chmod 755 {} +
/usr/bin/find "$stage/new" -type f -exec /bin/chmod 644 {} +
/bin/chmod 755 "$stage/new/AetherService" "$stage/new/AetherBridge" "$stage/new/Tools/bin/"*
verify_code "$stage/new/AetherService"; verify_code "$stage/new/AetherBridge"
[[ "$(code_hash "$stage/new/AetherService")" == "$service_hash" && "$(code_hash "$stage/new/AetherBridge")" == "$bridge_hash" ]] || fail "复制期间安装签名发生变化。"
[[ "$(/usr/bin/shasum -a 256 "$stage/new/Tools/tools-manifest.json" | /usr/bin/awk '{print $1}')" == "$manifest_hash" ]] || fail "复制期间工具清单发生变化。"
"$stage/new/AetherService" --verify-tools "$stage/new/Tools" >/dev/null 2>&1 || fail "冻结工具链完整性验证失败。"
# root 进程不得重新加载用户可写的 Homebrew 动态库。
for binary in "$stage/new/Tools/bin/bash" "$stage/new/Tools/bin/wg" "$stage/new/Tools/bin/wireguard-go" "$stage/new/Tools/lib/"*; do
  [[ -f "$binary" ]] || continue
  dependency_output="$(/usr/bin/otool -L "$binary")" || fail "无法检查工具链动态库。"
  while IFS= read -r dependency; do
    dependency="${dependency#"${dependency%%[![:space:]]*}"}"
    dependency="${dependency%% (compatibility version*}"
    case "$dependency" in
      /usr/lib/*|/System/Library/*) ;;
      @executable_path/../lib/*|@loader_path/*)
        library="${dependency##*/}"
        [[ "$library" =~ ^[A-Za-z0-9_.-]+$ && -f "$stage/new/Tools/lib/$library" ]] || fail "工具链动态库引用无效。"
        [[ "$dependency" == "@loader_path/$library" || "$dependency" == "@executable_path/../lib/$library" ]] || fail "工具链动态库引用越界。"
        ;;
      *) fail "工具链仍依赖未冻结的外部动态库。" ;;
    esac
  done < <(/usr/bin/tail -n +2 <<< "$dependency_output")
done
cat > "$stage/new/policy.json" <<POLICY
{"allowedUID":$allowed_uid,"clientRequirement":"identifier \"io.aether.wireguard\" and cdhash H\"$client_hash\""}
POLICY
/bin/chmod 644 "$stage/new/policy.json"
"$stage/new/AetherService" --verify-installation "$stage/new" >/dev/null 2>&1 || fail "后台服务安装包验证失败。"
cat > "$stage/new.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>$destination/AetherService</string></array>
<key>MachServices</key><dict><key>$label</key><true/></dict>
<key>UserName</key><string>root</string>
<key>RunAtLoad</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Background</string>
<key>Umask</key><integer>63</integer>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$stage/new.plist" >/dev/null
if [[ -e "$plist" ]]; then /bin/cp "$plist" "$stage/previous.plist"; had_plist=1; fi
if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
  was_loaded=1
  /bin/launchctl bootout "system/$label" >/dev/null 2>&1 || fail "无法停止旧版后台服务。"
  service_stopped=1
fi
# 停止监听之后再次检查，拒绝与刚开始的网络操作并发更新。
no_active_tunnel
if [[ -e "$destination" ]]; then /bin/mv "$destination" "$backup"; fi
replaced=1
/bin/mv "$stage/new" "$destination"
/bin/cp "$stage/new.plist" "$plist"
/usr/sbin/chown root:wheel "$plist"
/bin/chmod 644 "$plist"
/bin/launchctl bootstrap system "$plist" >/dev/null 2>&1 || fail "后台服务注册失败，已尝试恢复旧版。"
healthy=0
for attempt in {1..15}; do
  state="$(/bin/launchctl print "system/$label" 2>/dev/null || true)"
  if /usr/bin/grep -Eq '^[[:space:]]*state = running$' <<< "$state" && /usr/bin/grep -Eq '^[[:space:]]*pid = [1-9][0-9]*$' <<< "$state"; then
    healthy=$((healthy + 1))
    [[ "$healthy" -lt 2 ]] || break
  else healthy=0
  fi
  /bin/sleep 0.2
done
[[ "$healthy" -ge 2 ]] || fail "后台服务启动失败，已尝试恢复旧版。"
success=1
echo "Aether 后台服务已安装；日常连接和断开不再需要管理员密码。"

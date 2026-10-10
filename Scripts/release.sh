#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
source "$project/Scripts/common.sh"
[[ "$#" -le 1 ]] || fail "用法：Scripts/release.sh [输出目录]"
load_version
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || fail "当前 Release 仅发布 Apple Silicon；请在 arm64 macOS 上构建"
out="${1:-$project/dist}"
"$project/Scripts/check.sh"
"$project/Scripts/build.sh" "$out"
out="$(cd "$out" && pwd)"
archive="Aether-v$version-macos-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$out/Aether.app" "$out/$archive"
(
  cd "$out"
  /usr/bin/shasum -a 256 "$archive" > SHA256SUMS
  /usr/bin/shasum -a 256 -c SHA256SUMS
)
echo "Release 资产：$out/$archive"
echo "校验文件：$out/SHA256SUMS"
echo "这是 ad-hoc 签名的开发预览包，未做 Developer ID 签名或 Apple 公证。"

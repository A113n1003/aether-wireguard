#!/bin/bash
# 由构建脚本加载；不安装依赖，也不修改系统网络。

fail() {
  echo "错误：$*" >&2
  exit 1
}

load_version() {
  [[ -f "$project/VERSION" ]] || fail "缺少 VERSION 文件"
  version="$(cat "$project/VERSION")"
  [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "VERSION 必须使用 major.minor.patch 格式"
}

prepare_compiler() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "构建需要 macOS"
  architecture="$(uname -m)"
  case "$architecture" in
    arm64|x86_64) ;;
    *) fail "不支持的宿主架构：$architecture" ;;
  esac
  swiftc="$(/usr/bin/xcrun --find swiftc)"
  swift_version="$("$swiftc" --version)"
  [[ "$swift_version" =~ Swift\ version\ ([0-9]+)\. ]] || fail "无法识别 Swift 版本"
  [[ "${BASH_REMATCH[1]}" -ge 6 ]] || fail "需要 Swift 6.0 或更新版本"
  build="$project/.native-build/$architecture"
  mkdir -p "$build/cache"
  # 编译器要求 Swift 6+，语言模式与 Package.swift 保持一致。
  sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
  compiler=("$swiftc" -swift-version 5 -sdk "$sdk" -target "$architecture-apple-macosx14.0" -module-cache-path "$build/cache")
}

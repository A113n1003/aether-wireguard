#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
source "$project/Scripts/common.sh"
prepare_compiler
"${compiler[@]}" -emit-library -static -emit-module -module-name AetherCore "$project"/Sources/AetherCore/*.swift -emit-module-path "$build/AetherCore.swiftmodule" -o "$build/libAetherCore.a"
for name in ConfigurationChecks EngineChecks ServiceChecks; do
  "${compiler[@]}" -I "$build" -L "$build" -lAetherCore "$project/Scripts/$name.swift" -o "$build/$name"
  "$build/$name"
done

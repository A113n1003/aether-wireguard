#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
source "$project/Scripts/common.sh"
[[ "$#" -le 1 ]] || fail "用法：Scripts/build.sh [输出目录]"
load_version
build_number="${BUILD_NUMBER:-1}"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_NUMBER 必须是正整数"
prepare_compiler
out="${1:-$project/dist}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
stage="$(mktemp -d "$out/.aether-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
"${compiler[@]}" -O -emit-library -static -emit-module -module-name AetherCore "$project"/Sources/AetherCore/*.swift -emit-module-path "$build/AetherCore.swiftmodule" -o "$build/libAetherCore.a"
"${compiler[@]}" -O -I "$build" -L "$build" -lAetherCore "$project"/Sources/AetherBridge/main.swift -o "$build/AetherBridge"
"${compiler[@]}" -O -I "$build" -L "$build" -lAetherCore "$project"/Sources/AetherService/main.swift -o "$build/AetherService"
"${compiler[@]}" -O -parse-as-library -I "$build" -L "$build" -lAetherCore "$project"/Sources/AetherApp/*.swift -o "$build/Aether"
bundle="$stage/Aether.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$build/Aether" "$build/AetherBridge" "$bundle/Contents/MacOS/"
mkdir -p "$bundle/Contents/Resources/ConnectionService"
cp "$build/AetherService" "$build/AetherBridge" "$bundle/Contents/Resources/ConnectionService/"
cp "$project/Scripts/install-helper.sh" "$project/Scripts/uninstall-helper.sh" "$project/Scripts/package-helper-tools.py" "$bundle/Contents/Resources/"
cp "$project/LICENSE" "$project/THIRD_PARTY_NOTICES.md" "$bundle/Contents/Resources/"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Aether</string>
<key>CFBundleIdentifier</key><string>io.aether.wireguard</string>
<key>CFBundleName</key><string>Aether</string>
<key>CFBundleDisplayName</key><string>Aether</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>CFBundleIconFile</key><string>Aether</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -f "$project/Scripts/Icon.swift" ]]; then
  "${compiler[@]}" "$project/Scripts/Icon.swift" -o "$build/CreateIcon"
  "$build/CreateIcon" "$build/Aether.iconset"
  /usr/bin/python3 "$project/Scripts/package-icon.py" "$build/Aether.iconset" "$bundle/Contents/Resources/Aether.icns"
fi
/usr/bin/codesign --force --sign - --options runtime --identifier io.aether.wireguard.service "$bundle/Contents/Resources/ConnectionService/AetherService"
/usr/bin/codesign --force --sign - --options runtime "$bundle/Contents/Resources/ConnectionService/AetherBridge"
/usr/bin/codesign --force --sign - --options runtime "$bundle/Contents/MacOS/AetherBridge"
/usr/bin/codesign --force --sign - --options runtime "$bundle"
/usr/bin/codesign --verify --deep --strict "$bundle"
/usr/bin/plutil -lint "$bundle/Contents/Info.plist"
for executable in Aether AetherBridge; do
  [[ "$(/usr/bin/lipo -archs "$bundle/Contents/MacOS/$executable")" == "$architecture" ]] || fail "$executable 架构不匹配"
done
[[ "$(/usr/bin/lipo -archs "$bundle/Contents/Resources/ConnectionService/AetherService")" == "$architecture" ]] || fail "AetherService 架构不匹配"
rm -rf "$out/Aether.app"
mv "$bundle" "$out/Aether.app"
echo "已生成 $out/Aether.app（${version}，${architecture}，ad-hoc 签名，未公证）"

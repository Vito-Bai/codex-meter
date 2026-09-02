#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/outputs/Codex Meter.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

cd "$project_dir"
swift build -c release --arch arm64
swift build -c release --arch x86_64

mkdir -p "$macos_dir" "$resources_dir/Support"
lipo -create \
  ".build/arm64-apple-macosx/release/CodexMeter" \
  ".build/x86_64-apple-macosx/release/CodexMeter" \
  -output "$macos_dir/CodexMeter"
cp "Resources/Info.plist" "$contents_dir/Info.plist"
cp "Resources/Support/alipay.jpg" "$resources_dir/Support/alipay.jpg"
cp "Resources/Support/wechat.jpg" "$resources_dir/Support/wechat.jpg"
chmod +x "$macos_dir/CodexMeter"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"

#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/outputs/Codex Meter.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

cd "$project_dir"
swift build -c release

mkdir -p "$macos_dir"
cp ".build/release/CodexMeter" "$macos_dir/CodexMeter"
cp "Resources/Info.plist" "$contents_dir/Info.plist"
chmod +x "$macos_dir/CodexMeter"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"

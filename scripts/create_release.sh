#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
app_dir="$project_dir/outputs/Codex Meter.app"
dmg_path="$project_dir/outputs/Codex-Meter-$version-macOS-Universal.dmg"
checksum_path="$dmg_path.sha256"

"$project_dir/scripts/package_app.sh"
rm -f "$dmg_path" "$checksum_path"
hdiutil create \
  -volname "Codex Meter" \
  -srcfolder "$app_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"
shasum -a 256 "$dmg_path" > "$checksum_path"

echo "$dmg_path"
echo "$checksum_path"

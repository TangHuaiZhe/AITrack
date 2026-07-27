#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
bundle_dir="$project_dir/dist/TrackAI.app"
executable_dir="$bundle_dir/Contents/MacOS"

cd "$project_dir"
swift build -c release

rm -rf "$bundle_dir"
mkdir -p "$executable_dir"
cp ".build/release/SignalDesk" "$executable_dir/SignalDesk"
cp "AppBundle/Info.plist" "$bundle_dir/Contents/Info.plist"

codesign --force --deep --sign - "$bundle_dir"
echo "$bundle_dir"

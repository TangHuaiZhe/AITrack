#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
bundle_dir="$project_dir/dist/TrackAI.app"
executable_dir="$bundle_dir/Contents/MacOS"
trackai_signing_identity=${TRACKAI_SIGNING_IDENTITY:-}

if [[ -z "$trackai_signing_identity" ]]; then
    trackai_signing_identity=$(
        security find-identity -v -p codesigning |
            awk -F '"' '/"Developer ID Application:/ { print $2; exit }'
    )
fi

if [[ -z "$trackai_signing_identity" ]]; then
    trackai_signing_identity=$(
        security find-identity -v -p codesigning |
            awk -F '"' '/"Apple Development:/ { print $2; exit }'
    )
fi

if [[ -z "$trackai_signing_identity" ]]; then
    echo "TrackAI requires a valid Developer ID Application or Apple Development signing identity." >&2
    echo "Create or install one in Keychain Access, then run this script again." >&2
    exit 1
fi

cd "$project_dir"
swift build -c release

rm -rf "$bundle_dir"
mkdir -p "$executable_dir"
cp ".build/release/SignalDesk" "$executable_dir/SignalDesk"
cp "AppBundle/Info.plist" "$bundle_dir/Contents/Info.plist"

codesign --force --options runtime --sign "$trackai_signing_identity" "$bundle_dir"
codesign --verify --deep --strict --verbose=2 "$bundle_dir"
echo "$bundle_dir"

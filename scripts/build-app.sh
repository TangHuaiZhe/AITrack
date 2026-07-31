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
swift_build_args=(-c release)
if [[ "${TRACKAI_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then
    swift_build_args+=(--disable-sandbox)
fi
swift build "${swift_build_args[@]}"

rm -rf "$bundle_dir"
mkdir -p "$executable_dir"
cp ".build/release/SignalDesk" "$executable_dir/SignalDesk"
cp "AppBundle/Info.plist" "$bundle_dir/Contents/Info.plist"
mkdir -p "$bundle_dir/Contents/Resources"
cp "AppBundle/TrackAIIcon.icns" "$bundle_dir/Contents/Resources/TrackAIIcon.icns"

codesign --force --options runtime --sign "$trackai_signing_identity" "$bundle_dir"
codesign --verify --deep --strict --verbose=2 "$bundle_dir"
echo "$bundle_dir"

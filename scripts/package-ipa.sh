#!/usr/bin/env bash
# Packages an xcodebuild product into artifacts/Velora.ipa.
#
# The bundle layout matches what scripts/build-ipa.ps1 produces on Windows:
# Payload/Speedometer.app with Info.plist, the Speedometer executable, the two
# flattened AppIcon60x60 PNGs and PrivacyInfo.xcprivacy. Resources are added
# before the final ad-hoc signature so nothing lands after signing.
#
# Usage: scripts/package-ipa.sh <path/to/Speedometer.app> [output.ipa]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-}"
out="${2:-$root/artifacts/Velora.ipa}"

icon="$root/App/Resources/VeloraIcon.png"
privacy="$root/App/Resources/PrivacyInfo.xcprivacy"
executable="Speedometer"

usage() {
    echo "usage: $0 <path/to/Speedometer.app> [output.ipa]" >&2
    exit 2
}

[ -n "$app" ] || usage
[ -d "$app" ] || { echo "error: app bundle not found: $app" >&2; exit 1; }
[ -f "$icon" ] || { echo "error: app icon not found: $icon" >&2; exit 1; }
[ -f "$privacy" ] || { echo "error: privacy manifest not found: $privacy" >&2; exit 1; }
[ -f "$app/$executable" ] || { echo "error: $app contains no $executable executable" >&2; exit 1; }

# zip runs from the staging directory, so the output path must be absolute.
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

stage="$(mktemp -d "${TMPDIR:-/tmp}/velora-ipa.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/Payload"
bundle="$stage/Payload/Speedometer.app"
ditto "$app" "$bundle"

# xcodebuild runs with signing disabled, but never ship a stale bundle signature.
rm -rf "$bundle/_CodeSignature" "$bundle/embedded.mobileprovision"

# The Windows builder derives the flattened 60pt icons from the single source
# artwork, so the two paths stay visually identical.
sips -z 120 120 "$icon" --out "$bundle/AppIcon60x60@2x.png" >/dev/null
sips -z 180 180 "$icon" --out "$bundle/AppIcon60x60@3x.png" >/dev/null
cp "$privacy" "$bundle/PrivacyInfo.xcprivacy"

# xcodebuild leaves a PkgInfo behind; the Windows bundle has none.
rm -f "$bundle/PkgInfo"

# Ad-hoc signature of the executable, in the same place ldid -S signs it on
# Windows. codesign signs the enclosing bundle whenever the Mach-O sits inside
# one, which would add _CodeSignature/CodeResources and change the layout, so
# the executable is signed as a standalone file and copied back.
sign_target="$stage/$executable"
cp "$bundle/$executable" "$sign_target"
codesign --force --sign - --timestamp=none --identifier "com.velora.app" "$sign_target"
codesign --verify --strict "$sign_target"
cp "$sign_target" "$bundle/$executable"
rm -f "$sign_target"
chmod 755 "$bundle/$executable"
# codesign verifies the signature as standalone (above); checking the same file
# inside the bundle would demand _CodeSignature/CodeResources, which the
# Windows-compatible layout deliberately does not carry.

rm -f "$out"
# -D keeps directory entries out, matching the Windows archive layout.
(cd "$stage" && zip -q -r -X -D "$out" Payload)

echo "IPA written to $out ($(wc -c <"$out" | tr -d ' ') bytes)"

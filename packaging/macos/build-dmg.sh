#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root after Flutter and both Rust targets are built.
version="${1:?Usage: bash packaging/macos/build-dmg.sh X.Y.Z}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be X.Y.Z" >&2
  exit 1
fi
app="app/build/macos/Build/Products/Release/Openote.app"
test -d "$app"
core="rust/onote_core/target"
lipo -create \
  "$core/aarch64-apple-darwin/release/libonote_core.dylib" \
  "$core/x86_64-apple-darwin/release/libonote_core.dylib" \
  -output "$app/Contents/MacOS/libonote_core.dylib"

# Refuse to ship an app or importer that only works on one kind of MacBook.
lipo "$app/Contents/MacOS/Openote" -verify_arch arm64 x86_64
lipo "$app/Contents/MacOS/libonote_core.dylib" -verify_arch arm64 x86_64
# Ad-hoc signing is required on Apple Silicon. This is not Developer ID
# signing or notarization; Gatekeeper still requires a user override.
codesign --force --deep --sign - \
  --entitlements app/macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Openote.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Openote -srcfolder "$stage" -ov -format UDZO \
  "openote-$version-macos-universal.dmg"
hdiutil verify "openote-$version-macos-universal.dmg"

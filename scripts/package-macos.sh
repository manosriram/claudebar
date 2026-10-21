#!/bin/sh
# Produce standalone Intel, Apple Silicon, and universal app archives.
set -eu
cd "$(dirname "$0")/.."
version=$(cat VERSION)
release_dir="$PWD/dist/v$version"
mkdir -p "$release_dir"
for arch in arm64 x86_64; do
    APP_BUNDLE="$release_dir/$arch/ClaudeBar.app" BUILD_ARCH="$arch" ./build.sh
done

universal_app="$release_dir/universal/ClaudeBar.app"
mkdir -p "$release_dir/universal"
ditto "$release_dir/arm64/ClaudeBar.app" "$universal_app"
lipo -create "$release_dir/arm64/ClaudeBar.app/Contents/MacOS/ClaudeBar" \
    "$release_dir/x86_64/ClaudeBar.app/Contents/MacOS/ClaudeBar" \
    -output "$universal_app/Contents/MacOS/ClaudeBar"
for arch in arm64 x86_64; do
    lipo "$universal_app/Contents/MacOS/ClaudeBar" -verify_arch "$arch"
done

for arch in arm64 x86_64 universal; do
    app="$release_dir/$arch/ClaudeBar.app"
    plutil -lint "$app/Contents/Info.plist"
    test -s "$app/Contents/Resources/claude.svg"
    test -s "$app/Contents/Resources/openai.svg"
    codesign --force --sign - "$app"
    codesign --verify --deep --strict "$app"
    archive="$release_dir/ClaudeBar-$version-macos-$arch.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
    unzip -tq "$archive"
done
(cd "$release_dir" && shasum -a 256 ClaudeBar-*.zip > SHA256SUMS.txt)
echo "Release archives and checksums: $release_dir"

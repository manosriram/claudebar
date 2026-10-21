#!/bin/sh
# Builds ClaudeBar.app (menu-bar only, no Dock icon). Needs Xcode command line tools.
set -e
cd "$(dirname "$0")"
app_bundle=${APP_BUNDLE:-ClaudeBar.app}
build_arch=${BUILD_ARCH:-$(uname -m)}
build_version=$(cat VERSION)
minimum_macos=13.0
case "$build_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $build_arch" >&2; exit 1 ;; esac
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp Assets/claude.svg Assets/openai.svg "$app_bundle/Contents/Resources/"
swiftc -O -target "$build_arch-apple-macos$minimum_macos" ClaudeBar.swift -o "$app_bundle/Contents/MacOS/ClaudeBar"
cat > "$app_bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ClaudeBar</string>
  <key>CFBundleIdentifier</key><string>local.claudebar</string>
  <key>CFBundleName</key><string>ClaudeBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$build_version</string>
  <key>CFBundleVersion</key><string>$build_version</string>
  <key>LSMinimumSystemVersion</key><string>$minimum_macos</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
echo "Built $app_bundle ($build_arch, version $build_version)"

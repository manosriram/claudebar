#!/bin/sh
# Builds ClaudeBar.app (menu-bar only, no Dock icon). Needs Xcode command line tools.
set -e
cd "$(dirname "$0")"
mkdir -p ClaudeBar.app/Contents/MacOS
swiftc -O ClaudeBar.swift -o ClaudeBar.app/Contents/MacOS/ClaudeBar
cat > ClaudeBar.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ClaudeBar</string>
  <key>CFBundleIdentifier</key><string>local.claudebar</string>
  <key>CFBundleName</key><string>ClaudeBar</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
echo "Built ClaudeBar.app — run: open ClaudeBar.app"

#!/bin/zsh
# Builds "Claude Limits.app" into ~/Applications.
set -e
cd "${0:A:h}"
APP="$HOME/Applications/Claude Limits.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/ClaudeLimits"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.claude-limits</string>
  <key>CFBundleName</key><string>Claude Limits</string>
  <key>CFBundleExecutable</key><string>ClaudeLimits</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP"
echo "Built $APP"

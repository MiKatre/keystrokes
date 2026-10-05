#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

if pgrep -x Keystrokes >/dev/null 2>&1; then
  echo "Quit Keystrokes before rebuilding (use Quit in its dashboard)."
  exit 1
fi

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Install Apple's compiler first: xcode-select --install"
  exit 1
fi

swift build -c release
task_bin_dir="$(swift build -c release --show-bin-path)"
task_app_dir="$PWD/dist/Keystrokes.app"
mkdir -p "$task_app_dir/Contents/MacOS"
cp "$task_bin_dir/Keystrokes" "$task_app_dir/Contents/MacOS/Keystrokes"
cat > "$task_app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Keystrokes</string>
  <key>CFBundleIdentifier</key><string>io.mikatre.keystrokes</string>
  <key>CFBundleName</key><string>Keystrokes</string>
  <key>CFBundleDisplayName</key><string>Keystrokes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Standard ad-hoc signing for a local development build.
codesign --remove-signature "$task_app_dir"
codesign --force --sign - --identifier io.mikatre.keystrokes "$task_app_dir"
echo "Built: $task_app_dir"
if [[ "${1:-}" == "--run" ]]; then
  "$task_app_dir/Contents/MacOS/Keystrokes" --prepare-history
  task_install_dir="$HOME/Applications/Keystrokes.app"
  # Use /Applications on this Mac when the existing install belongs to this project.
  if [[ -d /Applications/Keystrokes.app ]]; then
    task_existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Keystrokes.app/Contents/Info.plist)"
    if [[ "$task_existing_id" != io.mikatre.keystrokes ]]; then
      echo 'A different app exists at /Applications/Keystrokes.app; leaving it unchanged.'
      exit 1
    fi
    task_install_dir="/Applications/Keystrokes.app"
  fi
  mkdir -p "${task_install_dir:h}"
  ditto "$task_app_dir" "$task_install_dir"
  open "$task_install_dir"
fi

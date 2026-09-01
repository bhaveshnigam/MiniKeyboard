#!/usr/bin/env bash
# Assembles MiniKeyboard.app from a built executable.
#
#   Scripts/make-app.sh <build-dir> <output-dir> <version>
set -euo pipefail

BUILD_DIR="${1:?build dir required}"
OUT_DIR="${2:?output dir required}"
VERSION="${3:-0.0.0}"

APP="$OUT_DIR/MiniKeyboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/MiniKeyboardApp" "$APP/Contents/MacOS/MiniKeyboard"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/MiniKeyboard.icns "$APP/Contents/Resources/MiniKeyboard.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so macOS will run it locally without a developer account.
codesign --force --deep --sign - "$APP" 2>/dev/null || {
  echo "warning: ad-hoc signing failed; the app may need right-click > Open" >&2
}

echo "Built $APP"

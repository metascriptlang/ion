#!/usr/bin/env bash
# Wrap an ion-built binary into a macOS .app bundle.
#
# Usage:
#   make-app.sh <binary-path> <app-name> <bundle-id> [<output-dir>] [flags...]
#
# Flags:
#   --url-scheme=NAME    Register a URL scheme (e.g. --url-scheme=myapp).
#   --icon=PATH.icns     Bundle an app icon. If omitted, app uses default.
#   --asset=PATH         Copy a file into Contents/Resources/. Pass multiple
#                        times. Loaded by ion via NSBundle fallback.
#   --sign[=IDENTITY]    Code-sign the bundle. No value → ad-hoc sign (-).
#                        Pass a Developer ID for distribution.
#   --hardened           Add `--options runtime` to codesign (Hardened Runtime).
#                        Required for notarization. Implies --sign.
#                        WARNING: Hardened Runtime rejects loading dylibs signed
#                        by a different Team ID (e.g. Homebrew SDL3). Either:
#                          - bundle dylibs into Frameworks/ and re-sign, OR
#                          - add `com.apple.security.cs.disable-library-validation`
#                            via --entitlements (weaker, but works for dogfood).
#   --entitlements=PATH  Bundle a .entitlements plist; passed to codesign.
#                        Required for hardened apps that need exceptions
#                        (e.g. JIT, debugger, disable-library-validation).
#
# Distribution workflow (after this script):
#   1. Sign with --hardened --sign="Developer ID Application: ..."
#   2. zip -r app.zip Foo.app
#   3. xcrun notarytool submit app.zip --keychain-profile NOTARY --wait
#   4. xcrun stapler staple Foo.app
#
# Example (dogfood):
#   make-app.sh out/debug/main "MyApp" com.example.myapp out \
#     --url-scheme=myapp --icon=assets/icon.icns --sign
#
# Example (distribution):
#   make-app.sh out/debug/main "MyApp" com.example.myapp out \
#     --url-scheme=myapp --icon=assets/icon.icns \
#     --hardened --entitlements=assets/app.entitlements \
#     --sign="Developer ID Application: Your Company (TEAMID)"

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <binary-path> <app-name> <bundle-id> [<output-dir>] [flags...]" >&2
  exit 2
fi

BINARY="$1"
APP_NAME="$2"
BUNDLE_ID="$3"
# OUT_DIR is the optional 4th positional. Must not absorb a flag — `${4:-...}`
# alone would happily take "--url-scheme=…" as OUT_DIR and break downstream
# rm/cp paths. Guard explicitly.
if [[ $# -ge 4 && "${4}" != --* ]]; then
  OUT_DIR="$4"
else
  OUT_DIR="$(dirname "$BINARY")"
fi
URL_SCHEME=""
ICON_PATH=""
DO_SIGN=""
SIGN_IDENTITY="-"
ASSETS=()
HARDENED=""
ENTITLEMENTS_PATH=""

shift 3
# 4th arg is OUT_DIR if it doesn't start with --; otherwise it's a flag
if [[ $# -gt 0 && "$1" != --* ]]; then shift; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url-scheme=*) URL_SCHEME="${1#*=}" ;;
    --icon=*)       ICON_PATH="${1#*=}" ;;
    --sign)         DO_SIGN="1" ;;
    --sign=*)       DO_SIGN="1"; SIGN_IDENTITY="${1#*=}" ;;
    --asset=*)      ASSETS+=("${1#*=}") ;;
    --hardened)     HARDENED="1"; DO_SIGN="1" ;;
    --entitlements=*) ENTITLEMENTS_PATH="${1#*=}" ;;
    *) echo "warn: unknown flag $1" >&2 ;;
  esac
  shift
done

if [[ ! -x "$BINARY" ]]; then
  echo "error: binary not found or not executable: $BINARY" >&2
  exit 1
fi

APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"

# Copy binary as the bundle's main executable.
EXEC_NAME="$(basename "$BINARY")"
cp "$BINARY" "$MACOS/$EXEC_NAME"
chmod +x "$MACOS/$EXEC_NAME"

# Bundle non-system dylib dependencies into Frameworks/, rewrite install_name
# so the binary loads from @rpath = ../Frameworks. Without this, the .app
# crashes on any machine that doesn't have Homebrew (or has a different
# version) installed.
EXT_DYLIBS=$(otool -L "$MACOS/$EXEC_NAME" \
  | tail -n +2 \
  | awk '{print $1}' \
  | grep -E "^/opt/homebrew|^/usr/local|^/opt/local" || true)

if [[ -n "$EXT_DYLIBS" ]]; then
  mkdir -p "$FRAMEWORKS"
  while IFS= read -r DYLIB; do
    [[ -z "$DYLIB" || ! -f "$DYLIB" ]] && continue
    NAME="$(basename "$DYLIB")"
    # Resolve symlinks so we copy the real binary, not the symlink.
    REAL=$(readlink -f "$DYLIB" 2>/dev/null || readlink "$DYLIB" || echo "$DYLIB")
    [[ ! -f "$REAL" ]] && REAL="$DYLIB"
    cp "$REAL" "$FRAMEWORKS/$NAME"
    chmod u+w "$FRAMEWORKS/$NAME"
    install_name_tool -id "@rpath/$NAME" "$FRAMEWORKS/$NAME" 2>/dev/null
    install_name_tool -change "$DYLIB" "@rpath/$NAME" "$MACOS/$EXEC_NAME" 2>/dev/null
    echo "  bundled: $NAME"
  done <<< "$EXT_DYLIBS"
  # Strip dev-host rpaths so the binary doesn't look at Homebrew/local paths
  # at runtime. ion already links @executable_path/../Frameworks, so dyld
  # finds the bundled dylib via that rpath.
  for OLD_RPATH in $(otool -l "$MACOS/$EXEC_NAME" | awk '/LC_RPATH/{f=1} f && /path /{print $2; f=0}' | grep -E "^/opt/homebrew|^/usr/local|^/opt/local"); do
    install_name_tool -delete_rpath "$OLD_RPATH" "$MACOS/$EXEC_NAME" 2>/dev/null && \
      echo "  stripped rpath: $OLD_RPATH"
  done
fi

# Bundle icon if provided.
ICON_ENTRY=""
if [[ -n "$ICON_PATH" ]]; then
  if [[ ! -f "$ICON_PATH" ]]; then
    echo "error: icon not found: $ICON_PATH" >&2; exit 1
  fi
  mkdir -p "$RESOURCES"
  cp "$ICON_PATH" "$RESOURCES/AppIcon.icns"
  ICON_ENTRY="
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

# Bundle additional assets (images, fonts, html files) into Resources/.
if [[ ${#ASSETS[@]} -gt 0 ]]; then
  mkdir -p "$RESOURCES"
  for ASSET in "${ASSETS[@]}"; do
    if [[ ! -f "$ASSET" ]]; then
      echo "error: asset not found: $ASSET" >&2; exit 1
    fi
    cp "$ASSET" "$RESOURCES/$(basename "$ASSET")"
  done
fi

URL_TYPES_BLOCK=""
if [[ -n "$URL_SCHEME" ]]; then
  URL_TYPES_BLOCK="
    <key>CFBundleURLTypes</key>
    <array>
      <dict>
        <key>CFBundleURLName</key>
        <string>$BUNDLE_ID.url</string>
        <key>CFBundleURLSchemes</key>
        <array>
          <string>$URL_SCHEME</string>
        </array>
      </dict>
    </array>"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>0.0.1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>$ICON_ENTRY$URL_TYPES_BLOCK
</dict>
</plist>
PLIST

# Sign last (codesign verifies bundle integrity, so all files must be in place).
# Sign inside-out: bundled dylibs first, then the app bundle. Hardened Runtime
# rejects loading dylibs that aren't signed, so this order matters.
if [[ -n "$DO_SIGN" ]]; then
  CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --timestamp=none)
  if [[ -n "$HARDENED" ]]; then
    CODESIGN_ARGS+=(--options runtime)
  fi

  if [[ -d "$FRAMEWORKS" ]]; then
    for DYLIB in "$FRAMEWORKS"/*.dylib; do
      [[ -f "$DYLIB" ]] || continue
      codesign "${CODESIGN_ARGS[@]}" "$DYLIB" 2>&1
    done
  fi

  if [[ -n "$ENTITLEMENTS_PATH" ]]; then
    if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
      echo "error: entitlements not found: $ENTITLEMENTS_PATH" >&2; exit 1
    fi
    CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
  fi
  codesign "${CODESIGN_ARGS[@]}" "$APP_DIR" 2>&1
fi

echo "built: $APP_DIR"

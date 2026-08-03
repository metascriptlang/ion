#!/usr/bin/env bash
# Wrap an ion-built binary into a Debian .deb installer.
#
# User flow (zero terminal, zero chmod, zero "Run as Program"):
#   1. Download MyApp-<arch>.deb
#   2. Double-click → GNOME Software / Discover opens
#   3. Click "Install"
#   4. MyApp appears in Activities (Super key) — click to launch
#
# Usage:
#   make-deb.sh <binary-path> <app-name> <bundle-id> [<output-dir>] [flags...]
#
# Flags:
#   --url-scheme=NAME    Register URL scheme — adds MimeType=x-scheme-handler/NAME
#                        to .desktop; xdg-open routes NAME:// URLs to the app.
#   --icon=PATH.png      Bundle an app icon (256x256 PNG recommended).
#   --asset=PATH         Copy a file into /usr/lib/<bundle-id>/resources/. Pass
#                        multiple times. ionResourcePath reads next-to-exe so
#                        ion-side asset lookups work transparently.
#   --version=X.Y.Z      Package version (default: 0.0.1).
#   --maintainer="N <e>" Debian Maintainer field (default: "Maintainer <maintainer@example.com>").
#   --description=TEXT   One-line package description.
#
# Example (dogfood):
#   make-deb.sh out/debug/helloWebview MyApp com.example.myapp out \
#     --url-scheme=myapp --icon=assets/icon.png \
#     --asset=examples/hello.html --version=0.1.0
#
# Output: <output-dir>/<bundle-id>_<version>_<arch>.deb
#
# Requires: dpkg-deb (ships in dpkg — present on Ubuntu/Debian + cross-builds
# via `apt install dpkg` on Fedora/Arch when generating .deb from non-Debian
# host). For Mac cross-build use `brew install dpkg`.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <binary-path> <app-name> <bundle-id> [<output-dir>] [flags...]" >&2
  exit 2
fi

BINARY="$1"
APP_NAME="$2"
BUNDLE_ID="$3"
if [[ $# -ge 4 && "${4}" != --* ]]; then
  OUT_DIR="$4"
else
  OUT_DIR="$(dirname "$BINARY")"
fi
URL_SCHEME=""
ICON_PATH=""
ASSETS=()
VERSION="0.0.1"
MAINTAINER="Maintainer <maintainer@example.com>"
DESCRIPTION="$APP_NAME — MyApp desktop app"

shift 3
if [[ $# -gt 0 && "$1" != --* ]]; then shift; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url-scheme=*)   URL_SCHEME="${1#*=}" ;;
    --icon=*)         ICON_PATH="${1#*=}" ;;
    --asset=*)        ASSETS+=("${1#*=}") ;;
    --version=*)      VERSION="${1#*=}" ;;
    --maintainer=*)   MAINTAINER="${1#*=}" ;;
    --description=*)  DESCRIPTION="${1#*=}" ;;
    *) echo "warn: unknown flag $1" >&2 ;;
  esac
  shift
done

if [[ ! -x "$BINARY" ]]; then
  echo "error: binary not found or not executable: $BINARY" >&2
  exit 1
fi

# Map host arch to Debian arch name. dpkg --print-architecture is canonical on
# Debian/Ubuntu; fall back to mapping uname output on non-Debian build hosts.
DEB_ARCH=""
if command -v dpkg >/dev/null 2>&1; then
  DEB_ARCH="$(dpkg --print-architecture)"
else
  case "$(uname -m)" in
    aarch64|arm64) DEB_ARCH="arm64" ;;
    x86_64)        DEB_ARCH="amd64" ;;
    armv7l)        DEB_ARCH="armhf" ;;
    *)             DEB_ARCH="$(uname -m)" ;;
  esac
fi

EXEC_NAME="$(basename "$BINARY")"
STAGE="$OUT_DIR/${BUNDLE_ID}_${VERSION}_${DEB_ARCH}"
OUT_FILE="$OUT_DIR/${BUNDLE_ID}_${VERSION}_${DEB_ARCH}.deb"

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN"
mkdir -p "$STAGE/usr/bin"
mkdir -p "$STAGE/usr/lib/$BUNDLE_ID/resources"
mkdir -p "$STAGE/usr/share/applications"
mkdir -p "$STAGE/usr/share/icons/hicolor/256x256/apps"

# 1. Stage the binary into /usr/lib/<bundle-id>/ (private prefix so multiple
# ion apps coexist without filename collisions in /usr/bin/). The user-facing
# launcher in /usr/bin/ is a small shell wrapper that cd's into the private
# resources dir before exec'ing — this is what makes the app discoverable as
# `<app-name>` in PATH while keeping resources next to the binary for
# ionResourcePath().
cp "$BINARY" "$STAGE/usr/lib/$BUNDLE_ID/$EXEC_NAME"
chmod +x "$STAGE/usr/lib/$BUNDLE_ID/$EXEC_NAME"

# 2. Assets into the private resources dir. ionResourcePath reads
# /proc/self/exe → /usr/lib/<bundle-id>/<binary> → strips basename →
# appends "resources" → /usr/lib/<bundle-id>/resources/. Matches Mac/Win.
for ASSET in "${ASSETS[@]+"${ASSETS[@]}"}"; do
  [[ -f "$ASSET" ]] || { echo "error: asset not found: $ASSET" >&2; exit 1; }
  cp "$ASSET" "$STAGE/usr/lib/$BUNDLE_ID/resources/$(basename "$ASSET")"
done

# 3. Launcher wrapper in /usr/bin/ — lowercase app-name for convention
# (e.g., `/usr/bin/myapp`). No CWD dependency: ion finds resources via
# /proc/self/exe, so wrapper just exec's into the real binary in /usr/lib.
LAUNCHER_NAME="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"
cat > "$STAGE/usr/bin/$LAUNCHER_NAME" <<LAUNCHER
#!/bin/sh
exec /usr/lib/$BUNDLE_ID/$EXEC_NAME "\$@"
LAUNCHER
chmod +x "$STAGE/usr/bin/$LAUNCHER_NAME"

# 4. Icon into hicolor theme. GNOME / KDE / Cinnamon resolve Icon=<bundle-id>
# in .desktop against this path automatically.
if [[ -n "$ICON_PATH" ]]; then
  [[ -f "$ICON_PATH" ]] || { echo "error: icon not found: $ICON_PATH" >&2; exit 1; }
  cp "$ICON_PATH" "$STAGE/usr/share/icons/hicolor/256x256/apps/$BUNDLE_ID.png"
fi

# 5. .desktop entry. Exec uses the /usr/bin/ launcher (which exec's the real
# binary). MimeType + StartupWMClass enable url-scheme routing + window
# grouping. NoDisplay=false means it shows in Activities.
MIME_LINE=""
if [[ -n "$URL_SCHEME" ]]; then
  MIME_LINE="MimeType=x-scheme-handler/$URL_SCHEME;"
fi
cat > "$STAGE/usr/share/applications/$BUNDLE_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=$DESCRIPTION
Exec=$LAUNCHER_NAME %u
Icon=$BUNDLE_ID
Categories=Utility;Network;
Terminal=false
StartupWMClass=$EXEC_NAME
$MIME_LINE
DESKTOP

# 6. Compute installed-size (KB) for control file — apt + GNOME Software
# display it before install so users see how much disk the app needs.
INSTALLED_SIZE_KB="$(du -sk "$STAGE/usr" | awk '{print $1}')"

# 7. control file — minimal viable set of Debian fields. Depends list pins
# runtime requirements: GTK3 + WebKitGTK + libnotify + appindicator. apt
# resolves these from the user's repos at install time (vs. bundling, which
# bloats the .deb to 100+ MB).
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: $BUNDLE_ID
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Installed-Size: $INSTALLED_SIZE_KB
Maintainer: $MAINTAINER
Depends: libgtk-3-0, libwebkit2gtk-4.1-0, libnotify4, libayatana-appindicator3-1, libx11-6, libsecret-1-0
Description: $DESCRIPTION
CONTROL

# 8. postinst — refresh desktop database + icon cache so the app shows up in
# Activities immediately (without logout). xdg-mime registers the URL scheme
# handler if --url-scheme was passed. All steps are best-effort: failure
# (e.g., minimal install without xdg tools) doesn't block the package.
cat > "$STAGE/DEBIAN/postinst" <<POSTINST
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"

# 9. postrm — symmetric cleanup after `apt remove`. Same best-effort policy.
cat > "$STAGE/DEBIAN/postrm" <<POSTRM
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi
POSTRM
chmod 755 "$STAGE/DEBIAN/postrm"

# 10. Pack. dpkg-deb --build = stage dir → .deb. -Zxz = xz compression (smallest
# size; gzip is faster but ~20% larger; zstd is fastest but requires dpkg 1.21+
# everywhere, which Debian stable doesn't have yet).
rm -f "$OUT_FILE"
dpkg-deb --build -Zxz "$STAGE" "$OUT_FILE" >/dev/null

if [[ ! -f "$OUT_FILE" ]]; then
  echo "error: dpkg-deb did not produce $OUT_FILE" >&2
  exit 1
fi

echo "built: $OUT_FILE"

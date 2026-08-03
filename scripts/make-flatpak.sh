#!/usr/bin/env bash
# Wrap an ion-built binary into a Flatpak bundle for cross-distro install.
#
# User flow (modern Linux UX — works on Ubuntu/Fedora/Arch/openSUSE/...):
#   1. User runs: flatpak install --user myapp.flatpak  (or downloads from Flathub)
#   2. Software Center / Discover / App Center sees the app + shows Install button
#   3. Click Install → MyApp appears in Activities (Super) like any native app
#   4. Click to launch — no terminal, no chmod, no Run-as-Program prompt
#
# Usage:
#   make-flatpak.sh <binary-path> <app-name> <bundle-id> [<output-dir>] [flags...]
#
# Flags:
#   --url-scheme=NAME    Register URL scheme (MimeType=x-scheme-handler/NAME).
#   --icon=PATH.png      Bundle an app icon (256x256 PNG; SVG OK too).
#   --asset=PATH         Copy a file into /app/bin/resources/. Repeatable.
#                        ionResourcePath reads /proc/self/exe → /app/bin/ →
#                        appends "resources" → resolves here. Matches Mac/Win.
#   --version=X.Y.Z      Package version (default: 0.0.1).
#   --summary=TEXT       One-line summary (AppStream metainfo).
#   --description=TEXT   One-paragraph description (AppStream metainfo).
#   --install            After build, install the .flatpak into the user's
#                        Flatpak so it shows in Activities immediately.
#
# Output:
#   <output-dir>/<bundle-id>_<version>.flatpak    (single-file bundle)
#   <output-dir>/flatpak-build/                   (build state — re-used on rebuild)
#
# Requires: flatpak + flatpak-builder. The GNOME 46 runtime + SDK download
# (~1.5 GB) happens once via `flatpak install flathub org.gnome.Platform//46
# org.gnome.Sdk//46`; subsequent builds reuse the cached runtime.

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
SUMMARY="$APP_NAME — MyApp desktop app"
DESCRIPTION="The team layer for Studios of one. AI-native, MCP-first."
INSTALL_AFTER=""

shift 3
if [[ $# -gt 0 && "$1" != --* ]]; then shift; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url-scheme=*)   URL_SCHEME="${1#*=}" ;;
    --icon=*)         ICON_PATH="${1#*=}" ;;
    --asset=*)        ASSETS+=("${1#*=}") ;;
    --version=*)      VERSION="${1#*=}" ;;
    --summary=*)      SUMMARY="${1#*=}" ;;
    --description=*)  DESCRIPTION="${1#*=}" ;;
    --install)        INSTALL_AFTER="1" ;;
    *) echo "warn: unknown flag $1" >&2 ;;
  esac
  shift
done

if [[ ! -x "$BINARY" ]]; then
  echo "error: binary not found or not executable: $BINARY" >&2
  exit 1
fi
if ! command -v flatpak-builder >/dev/null 2>&1; then
  echo "error: flatpak-builder not installed (apt install flatpak-builder)" >&2
  exit 1
fi

EXEC_NAME="$(basename "$BINARY")"
BUILD_DIR="$OUT_DIR/flatpak-build"
STAGE="$BUILD_DIR/stage"
REPO="$BUILD_DIR/repo"
OUT_FILE="$OUT_DIR/${BUNDLE_ID}_${VERSION}.flatpak"

rm -rf "$STAGE"
mkdir -p "$STAGE/sources/resources"

# Vendor Flathub's official shared-modules into the build stage. Manifest
# references `shared-modules/libayatana-appindicator/...` relative to itself.
# Shallow-clone (~5 MB); we don't pin a commit because Flathub maintains
# the head as canonical — local re-clones pick up upstream fixes.
SHARED_DIR="$STAGE/shared-modules"
if [[ ! -d "$SHARED_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/flathub/shared-modules.git "$SHARED_DIR" >/dev/null 2>&1
fi

# 1. Stage binary + assets in a sources/ subdir that the manifest references.
cp "$BINARY" "$STAGE/sources/$EXEC_NAME"
chmod +x "$STAGE/sources/$EXEC_NAME"
for ASSET in "${ASSETS[@]+"${ASSETS[@]}"}"; do
  [[ -f "$ASSET" ]] || { echo "error: asset not found: $ASSET" >&2; exit 1; }
  cp "$ASSET" "$STAGE/sources/resources/$(basename "$ASSET")"
done

# 2. Icon. Flatpak requires Icon=<bundle-id> resolution against
# /app/share/icons/hicolor/. Stub a 1x1 transparent PNG if none supplied.
ICON_DEST="$STAGE/sources/$BUNDLE_ID.png"
if [[ -n "$ICON_PATH" ]]; then
  [[ -f "$ICON_PATH" ]] || { echo "error: icon not found: $ICON_PATH" >&2; exit 1; }
  cp "$ICON_PATH" "$ICON_DEST"
else
  # Valid 1x1 transparent PNG (67 bytes, CRC-correct). Inline base64 so the
  # stub is deterministic — hand-rolled printf bytes risk bitrot from shell
  # escape variance, and Flatpak's icon validator rejects malformed PNGs.
  echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 -d > "$ICON_DEST"
fi

# 3. .desktop entry. Exec uses the launcher name = $EXEC_NAME. MimeType
# routes URL-scheme links to the app via xdg-open inside the sandbox.
MIME_LINE=""
if [[ -n "$URL_SCHEME" ]]; then
  MIME_LINE="MimeType=x-scheme-handler/$URL_SCHEME;"
fi
cat > "$STAGE/sources/$BUNDLE_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=$SUMMARY
Exec=$EXEC_NAME %u
Icon=$BUNDLE_ID
Categories=Utility;Network;
Terminal=false
StartupWMClass=$EXEC_NAME
$MIME_LINE
DESKTOP

# 4. AppStream metainfo — Flathub requires this for store listing. For local
# build / private distribution the minimal set below is enough. Iterate on
# screenshots + content_rating when prepping a Flathub submission.
CURRENT_DATE="$(date -u +%Y-%m-%d)"
cat > "$STAGE/sources/$BUNDLE_ID.metainfo.xml" <<METAINFO
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$BUNDLE_ID</id>
  <name>$APP_NAME</name>
  <summary>$SUMMARY</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>LicenseRef-proprietary</project_license>
  <description>
    <p>$DESCRIPTION</p>
  </description>
  <launchable type="desktop-id">$BUNDLE_ID.desktop</launchable>
  <releases>
    <release version="$VERSION" date="$CURRENT_DATE"/>
  </releases>
  <content_rating type="oars-1.1"/>
</component>
METAINFO

# 5. Flatpak manifest. Uses simple buildsystem — copy pre-built binary +
# assets into /app/. Finish-args expose the sandbox holes ion needs:
#   - share=ipc       cross-process IPC (X11 protocol uses it)
#   - share=network   webview HTTP/HTTPS + future MCP backends
#   - socket=fallback-x11 + socket=wayland   display under either session
#   - device=dri      GPU acceleration for WebKit compositor
#   - talk-name=org.freedesktop.Notifications   libnotify
#   - talk-name=org.kde.StatusNotifierWatcher   appindicator tray
#   - talk-name=org.ayatana.indicator.application.service   legacy tray
#   - filesystem=xdg-documents, xdg-download   file dialog default scopes
#   - filesystem=home:ro   broader read scope (MyApp needs to repro Cubes
#                          across user-cloned repos — start read-only, relax
#                          per-scope later if user grants explicit permission)
cat > "$STAGE/$BUNDLE_ID.yaml" <<MANIFEST
app-id: $BUNDLE_ID
runtime: org.gnome.Platform
runtime-version: '46'
sdk: org.gnome.Sdk
command: $EXEC_NAME
# Skip AppStream compose for local dev — strict on metainfo screenshots /
# developer_name / SPDX licensing we don't need until Flathub submission.
# Flip to true (default) when prepping the public store listing.
appstream-compose: false
finish-args:
  - --share=ipc
  - --share=network
  - --socket=fallback-x11
  - --socket=wayland
  - --device=dri
  - --talk-name=org.freedesktop.Notifications
  - --talk-name=org.kde.StatusNotifierWatcher
  - --talk-name=org.ayatana.indicator.application.service
  - --talk-name=org.freedesktop.secrets
  - --filesystem=xdg-documents
  - --filesystem=xdg-download
  - --filesystem=home:ro
modules:
  # libayatana-appindicator chain — pulled from Flathub's official
  # shared-modules repo (battle-tested across Discord, Element, Sunshine,
  # etc.). Bundles the full graph: intltool → libdbusmenu → ayatana-ido →
  # libayatana-indicator → libayatana-appindicator, with the
  # HAVE_VALGRIND autotools patch and version pins. Cloned into the build
  # stage by make-flatpak.sh before flatpak-builder runs.
  - shared-modules/libayatana-appindicator/libayatana-appindicator-gtk3.json
  - name: myapp
    buildsystem: simple
    build-commands:
      - install -Dm755 $EXEC_NAME /app/bin/$EXEC_NAME
      - install -d /app/bin/resources
      - test -d resources && cp -r resources/* /app/bin/resources/ || true
      - install -Dm644 $BUNDLE_ID.desktop /app/share/applications/$BUNDLE_ID.desktop
      - install -Dm644 $BUNDLE_ID.png /app/share/icons/hicolor/256x256/apps/$BUNDLE_ID.png
      - install -Dm644 $BUNDLE_ID.metainfo.xml /app/share/metainfo/$BUNDLE_ID.metainfo.xml
    sources:
      - type: dir
        path: sources
MANIFEST

# 6. Build + bundle. flatpak-builder packs into local OSTree repo (REPO),
# then `flatpak build-bundle` exports a single-file .flatpak for distribution.
rm -rf "$BUILD_DIR/build-cache" "$BUILD_DIR/build-dir"
flatpak-builder \
  --force-clean \
  --disable-rofiles-fuse \
  --repo="$REPO" \
  --state-dir="$BUILD_DIR/build-cache" \
  "$BUILD_DIR/build-dir" \
  "$STAGE/$BUNDLE_ID.yaml" \
  2>&1 | tail -15

rm -f "$OUT_FILE"
flatpak build-bundle "$REPO" "$OUT_FILE" "$BUNDLE_ID" 2>&1 | tail -5

if [[ ! -f "$OUT_FILE" ]]; then
  echo "error: build-bundle did not produce $OUT_FILE" >&2
  exit 1
fi

echo "built: $OUT_FILE"

# 7. Optional install for immediate testing. --user installs without root,
# scoped to the current user. Re-installs (replace) on rebuild.
if [[ -n "$INSTALL_AFTER" ]]; then
  flatpak install --user --or-update --noninteractive -y "$OUT_FILE"
  echo "installed: flatpak run $BUNDLE_ID"
fi

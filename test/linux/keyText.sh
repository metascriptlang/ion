#!/usr/bin/env bash
# Builds keyText.c against the C sources src/ipc.ms compiles on Linux and runs it under Xvfb with GTK's simple IM.
set -euo pipefail
export WAYLAND_DISPLAY=ion-probe-no-wayland
cd "$(dirname "$0")/../.."
rt=$(dirname "$(readlink -f "$(command -v msc)")")
[ -d "$rt/runtime" ] || rt=$(dirname "$rt")
out=$(mktemp -d)
srcs=$(sed -n 's/^[[:space:]]*@compile("\.\/\(platform\/\(common\|linux\)\/[^"]*\)");/src\/\1/p' src/ipc.ms)
pkgs="gtk4 webkitgtk-6.0 libnotify ayatana-appindicator-glib libsecret-1 x11 xtst"
cc -std=gnu11 -O1 -g -w -Isrc -I"$rt" $(pkg-config --cflags $pkgs) test/linux/keyText.c test/linux/msStubs.c $srcs \
    -Wl,--wrap=ion_input_push_record $(pkg-config --libs $pkgs) -lm -o "$out/keyText"
echo "== simple IM"
GTK_IM_MODULE=gtk-im-context-simple xvfb-run -a "$out/keyText"
# An input method that commits after filter_keypress returns, as IBus and fcitx5 do on a desktop.
# A private bus and display; the daemon this run starts is killed by its pid at the end.
if command -v ibus-daemon >/dev/null; then
    echo "== ibus"
    xvfb-run -a dbus-run-session -- sh -c 'ibus-daemon --panel=disable --emoji-extension=disable >/dev/null 2>&1 & f=$!; sleep 3; IBUS_ENABLE_SYNC_MODE=0 GTK_IM_MODULE=ibus timeout 60 "$0"; s=$?; kill $f; wait $f 2>/dev/null; exit $s' "$out/keyText"
fi

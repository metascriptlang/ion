#!/usr/bin/env bash
# Builds keyText.c against the C sources src/ipc.ms compiles on Linux and runs it under Xvfb with each input method.
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
rc=0
echo "== simple IM"
GTK_IM_MODULE=gtk-im-context-simple xvfb-run -a "$out/keyText" || rc=1
echo "== ion-probe-async (re-delivers each event as fcitx5-gtk does)"
GTK_IM_MODULE=ion-probe-async xvfb-run -a "$out/keyText" || rc=1
# IBus on a private bus and display; the daemon this run starts is killed by its pid at the end.
# IBUS_ENABLE_SYNC_MODE=0 commits after filter_keypress returns; unset, GTK4's ibus module is synchronous.
if command -v ibus-daemon >/dev/null; then
    for sync in 0 1; do
        echo "== ibus, IBUS_ENABLE_SYNC_MODE=$sync"
        IBUS_ENABLE_SYNC_MODE=$sync xvfb-run -a dbus-run-session -- sh -c 'ibus-daemon --panel=disable --emoji-extension=disable >/dev/null 2>&1 & f=$!; sleep 3; GTK_IM_MODULE=ibus timeout 60 "$0"; s=$?; kill $f; wait $f 2>/dev/null; exit $s' "$out/keyText" || rc=1
    done
fi
exit $rc

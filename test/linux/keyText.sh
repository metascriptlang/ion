#!/usr/bin/env bash
# Builds keyText.c against the C sources src/ipc.ms compiles on Linux and runs it under Xvfb with GTK's simple IM.
set -euo pipefail
export WAYLAND_DISPLAY=ion-probe-no-wayland GTK_IM_MODULE=gtk-im-context-simple
cd "$(dirname "$0")/../.."
rt=$(dirname "$(readlink -f "$(command -v msc)")")
[ -d "$rt/runtime" ] || rt=$(dirname "$rt")
out=$(mktemp -d)
srcs=$(sed -n 's/^[[:space:]]*@compile("\.\/\(platform\/\(common\|linux\)\/[^"]*\)");/src\/\1/p' src/ipc.ms)
pkgs="gtk4 webkitgtk-6.0 libnotify ayatana-appindicator-glib libsecret-1 x11 xtst"
cc -std=gnu11 -O1 -g -w -Isrc -I"$rt" $(pkg-config --cflags $pkgs) test/linux/keyText.c test/linux/msStubs.c $srcs \
    -Wl,--wrap=ion_input_push_record $(pkg-config --libs $pkgs) -lm -o "$out/keyText"
xvfb-run -a "$out/keyText"

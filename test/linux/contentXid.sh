#!/usr/bin/env bash
# Builds contentXid.c against the C sources src/ipc.ms compiles on Linux and runs it under Xvfb,
# with and without ionRequestX11, at scale 1 and 2, with and without a client-side header bar,
# and on Broadway for a display that is not X11.
# Needs the GTK dev packages of CLAUDE.md, xvfb-run and the msc runtime headers beside `msc`.
set -euo pipefail
# libwayland falls back to wayland-0 when WAYLAND_DISPLAY is unset: name none, so no run reaches a live session.
export WAYLAND_DISPLAY=ion-probe-no-wayland
cd "$(dirname "$0")/../.."
rt=$(dirname "$(readlink -f "$(command -v msc)")")
[ -d "$rt/runtime" ] || rt=$(dirname "$rt")
out=$(mktemp -d)
srcs=$(sed -n 's/^[[:space:]]*@compile("\.\/\(platform\/\(common\|linux\)\/[^"]*\)");/src\/\1/p' src/ipc.ms)
pkgs="gtk4 webkitgtk-6.0 libnotify ayatana-appindicator-glib libsecret-1 x11"
# VOID_SRC=<void>/src/platform also draws through Void's Linux views (GLES3 over EGL, as Xvfb needs).
extra=()
if [ -n "${VOID_SRC:-}" ]; then
    pkgs="$pkgs egl glesv2"
    extra=(-DION_PROBE_VOID -DVOID_GLES3 -I"$VOID_SRC" "$VOID_SRC/linux/window.c" -lXcursor -lXi -ldl)
fi
cc -std=gnu11 -O1 -g -w -Isrc -I"$rt" $(pkg-config --cflags $pkgs) test/linux/contentXid.c test/linux/msStubs.c $srcs \
    "${extra[@]}" $(pkg-config --libs $pkgs) -lm -o "$out/contentXid"
status=0
run() { echo "== $*"; env "$@" || status=1; }
run xvfb-run -a "$out/contentXid" x11
run xvfb-run -a "$out/contentXid" plain
run xvfb-run -a "$out/contentXid" x11 header
run GDK_SCALE=2 xvfb-run -a "$out/contentXid" x11 header
if command -v gtk4-broadwayd >/dev/null; then
    gtk4-broadwayd :5 & bpid=$!
    sleep 1
    run GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 "$out/contentXid" plain
    kill $bpid
else
    echo "== gtk4-broadwayd missing: the not-X11 path (returns 0) is not run"
fi
exit $status

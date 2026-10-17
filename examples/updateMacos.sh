#!/bin/bash
# OTA end to end on macOS through a manifest server on localhost: builds version 1.0.0 and
# 2.0.0 of examples/updateMacos.ms, signs 2.0.0's .dmg and a web bundle .zip with a fresh
# Ed25519 key, launches 1.0.0 and waits for 2.0.0 to be relaunched in its place.
#
# Usage, from the repo root: bash examples/updateMacos.sh [work dir]
# LOCKED=1 makes the installed app's directory read-only, so the install asks for an admin
# password; Cancel there must leave version 1.0.0 in place.
# LibreSSL (/usr/bin/openssl) has no Ed25519; OPENSSL names an OpenSSL 3.
set -euo pipefail

OPENSSL=${OPENSSL:-/opt/homebrew/opt/openssl@3/bin/openssl}
DIR=${1:-/tmp/ion-ota-macos}
PORT=${PORT:-$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')}
APP=UpdateMacos

[ -d "$DIR/apps" ] && chmod u+w "$DIR/apps"
rm -rf "$DIR"
mkdir -p "$DIR/v1" "$DIR/v2" "$DIR/dmg" "$DIR/serve" "$DIR/apps" "$DIR/web" "$DIR/webSrc"
msc build examples/updateMacos.ms
for v in 1 2; do
	echo "$v.0.0" > "$DIR/v$v/version.txt"
	scripts/make-app.sh out/debug/updateMacos "$APP" dev.ion.updatemacos "$DIR/v$v" --sign --asset="$DIR/v$v/version.txt" >/dev/null
done

ARTIFACT="$DIR/serve/$APP-2.0.0.dmg"
cp -R "$DIR/v2/$APP.app" "$DIR/dmg/"
hdiutil create -quiet -fs HFS+ -volname "$APP" -srcfolder "$DIR/dmg" "$ARTIFACT"
WEB="$DIR/serve/web-2.0.0.zip"
echo "<h1>web 1.0.0</h1>" > "$DIR/web/index.html"
echo "<h1>web 2.0.0</h1>" > "$DIR/webSrc/index.html"
(cd "$DIR/webSrc" && zip -q "$WEB" index.html)
"$OPENSSL" genpkey -algorithm ed25519 -out "$DIR/key.pem"
PUB=$("$OPENSSL" pkey -in "$DIR/key.pem" -pubout -outform DER | tail -c 32 | base64)
sign() { "$OPENSSL" pkeyutl -sign -inkey "$DIR/key.pem" -rawin -in "$1" | base64; }
asset() {
	printf '{ "platform": "%s", "url": "http://127.0.0.1:%s/%s", "size": %s, "hash": "sha256:%s", "signature": "ed25519:%s" }' \
		"$1" "$PORT" "$(basename "$2")" "$(stat -f %z "$2")" "$(shasum -a 256 "$2" | cut -d' ' -f1)" "$(sign "$2")"
}
cat > "$DIR/serve/manifest" <<EOF
{
  "version": "2.0.0",
  "publishedAt": "2026-10-18T00:00:00Z",
  "releaseNotes": "updateMacos e2e",
  "assets": [
    $(asset darwin-aarch64 "$ARTIFACT"),
    $(asset web "$WEB")
  ]
}
EOF

python3 -I -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR/serve" >"$DIR/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1

cp -R "$DIR/v1/$APP.app" "$DIR/apps/"
[ "${LOCKED:-}" = 1 ] && chmod a-w "$DIR/apps"
open -W -n --stdout "$DIR/v1.out" --stderr "$DIR/v1.err" \
	--env "ION_OTA_MANIFEST=http://127.0.0.1:$PORT/manifest" --env "ION_OTA_KEY=$PUB" --env "ION_OTA_WEB_DIR=$DIR/web" \
	"$DIR/apps/$APP.app"
cat "$DIR/v1.out"
for _ in $(seq 1 100); do
	[ -f "$DIR/updateMacos.relaunched" ] && break
	sleep 0.1
done
RELAUNCHED=$(cat "$DIR/updateMacos.relaunched" 2>/dev/null || echo none)
INSTALLED=$(cat "$DIR/apps/$APP.app/Contents/Resources/version.txt")
LEFT=$(ls -A "$DIR/apps")
OWNER=$(stat -f %Su "$DIR/apps/$APP.app/Contents/Info.plist")
if [ "$RELAUNCHED" = "2.0.0" ] && [ "$INSTALLED" = "2.0.0" ] && [ "$OWNER" = "$(id -un)" ] && grep -q 2.0.0 "$DIR/web/index.html"; then
	echo "updateMacos: PASS (relaunched as $RELAUNCHED; $DIR/apps holds: $(echo $LEFT); owned by $OWNER)"
else
	echo "updateMacos: FAIL (relaunched: $RELAUNCHED, installed: $INSTALLED, owned by $OWNER)"
	cat "$DIR/v1.err"
	exit 1
fi

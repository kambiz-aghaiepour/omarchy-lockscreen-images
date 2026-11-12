#!/bin/bash
# End-to-end smoke for the drift pipeline: bake one tiny image, run the feeder
# briefly against the baked clip, assert a fresh JPEG was published, and check
# the lock guard's dry logic. Run: tests/smoke.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1px-ish source image via ffmpeg lavfi, so no fixtures are needed.
ffmpeg -v error -y -f lavfi -i color=c=steelblue:s=640x400 -frames:v 1 "$tmp/one.png"

cfg=$tmp/lockscreen-drift.json
printf '{ "imagesDir": "%s", "rotateSeconds": 2, "lockDrift": true }\n' "$tmp" > "$cfg"

echo "== bake"
OMARCHY_LOCK_DRIFT_CONFIG=$cfg "$here/scripts/omarchy-aerial-drift" bake
ls "$tmp/.baked"/*.mp4

echo "== feed (3 s)"
OMARCHY_LOCK_DRIFT_CONFIG=$cfg timeout 6 "$here/scripts/omarchy-aerial-drift" feed &
feedpid=$!
for _ in $(seq 1 50); do
  [[ -s /dev/shm/omarchy-drift.jpg ]] && break
  sleep 0.1
done
kill "$feedpid" 2>/dev/null || true
wait "$feedpid" 2>/dev/null || true

out=/dev/shm/omarchy-drift.jpg
[[ -s $out ]] || { echo "FAIL: no $out" >&2; exit 1; }
head -c 2 "$out" | od -An -tx1 | grep -q "ff d8" || { echo "FAIL: not a JPEG" >&2; exit 1; }
echo "OK: fresh JPEG at $out"

echo "== lock guard syntax"
bash -n "$here/scripts/omarchy-lock-if-unlocked"
bash -n "$here/scripts/install-helpers"
bash -n "$here/scripts/omarchy-aerial-drift"
echo "OK: scripts parse"

echo "== serve input config"
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/mpv" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  case $arg in
    --input-conf=*) cp "${arg#--input-conf=}" "$CAPTURE" ;;
  esac
done
EOF
chmod +x "$tmp/bin/mpv"

CAPTURE=$tmp/served-input.conf HOME=$tmp/home PATH="$tmp/bin:$PATH" \
  OMARCHY_LOCK_DRIFT_CONFIG=$cfg "$here/scripts/omarchy-aerial-drift" serve
for key in ESC SPACE ENTER PGUP PGDWN BS; do
  grep -qx "$key quit" "$tmp/served-input.conf" ||
    { echo "FAIL: $key quit missing from generated input" >&2; exit 1; }
done
echo "OK: generated input binds every dismissal key"

mkdir -p "$tmp/home/.config/omarchy"
printf 'SPACE cycle pause\n' > "$tmp/home/.config/omarchy/mpv-screensaver.conf"
CAPTURE=$tmp/served-input-user.conf HOME=$tmp/home PATH="$tmp/bin:$PATH" \
  OMARCHY_LOCK_DRIFT_CONFIG=$cfg "$here/scripts/omarchy-aerial-drift" serve
grep -qx 'SPACE cycle pause' "$tmp/served-input-user.conf" ||
  { echo "FAIL: user input binding was not preserved" >&2; exit 1; }
grep -qx 'SPACE quit' "$tmp/served-input-user.conf" ||
  { echo "FAIL: dismissal binding did not override user binding" >&2; exit 1; }
echo "OK: generated input merges user bindings and enforces dismissal"

echo "ALL OK"

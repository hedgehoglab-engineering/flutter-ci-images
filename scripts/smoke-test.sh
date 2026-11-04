#!/usr/bin/env bash
# Run the smoke package inside an image with no network access.
# Usage: smoke-test.sh <image>
set -euo pipefail

[ $# -eq 1 ] || { echo "Usage: $0 <image>" >&2; exit 2; }
image="$1"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
# The root run leaves root-owned files in the bind mount; on a Linux host only
# root can delete them, so clean up from inside the image first.
cleanup() {
  docker run --rm --platform linux/amd64 --network none -v "$work:/w" "$image" \
    bash -c 'rm -rf /w/root /w/user' >/dev/null 2>&1 || true
  rm -rf "$work" 2>/dev/null || true
}
trap cleanup EXIT

# prepare <dir>: fresh copy of the smoke package without generated files.
prepare() {
  cp -R "$repo_root/smoke" "$work/$1"
  rm -rf "$work/$1/.dart_tool" "$work/$1/pubspec.lock" "$work/$1/test/goldens"
}

# run_smoke <dir> <script> [extra docker args...]
run_smoke() {
  local dir="$1" script="$2"
  shift 2
  docker run --rm --platform linux/amd64 --network none \
    "$@" -v "$work/$dir:/workspace" "$image" bash -euxo pipefail -c "$script"
}

echo "== Run 1: root user"
prepare root
run_smoke root '
  flutter --version
  flutter doctor -v || true
  flutter pub get --offline
  flutter test --update-goldens
  flutter test
'

echo "== Run 2: non-root user 1001:1001"
prepare user
chmod -R a+rwX "$work/user"
run_smoke user '
  flutter --version
  flutter pub get --offline
  flutter test --update-goldens
  flutter test
' --user 1001:1001 -e HOME=/tmp

echo "Smoke test passed for $image"

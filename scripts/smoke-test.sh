#!/usr/bin/env bash
# Run the smoke package inside an image with no network access.
# Usage: smoke-test.sh <image>
set -euo pipefail

[ $# -eq 1 ] || { echo "Usage: $0 <image>" >&2; exit 2; }
image="$1"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# run_smoke <script> [extra docker args...]
run_smoke() {
  local script="$1"
  shift
  docker run --rm --platform linux/amd64 --network none \
    "$@" -v "$work/smoke:/workspace" "$image" bash -euxo pipefail -c "$script"
}

echo "== Run 1: root user"
rm -rf "$work/smoke"
cp -R "$repo_root/smoke" "$work/smoke"
rm -rf "$work/smoke/.dart_tool" "$work/smoke/pubspec.lock" "$work/smoke/test/goldens"
run_smoke '
  flutter --version
  flutter doctor -v || true
  flutter pub get --offline
  flutter test --update-goldens
  flutter test
'

echo "== Run 2: non-root user 1001:1001"
rm -rf "$work/smoke"
cp -R "$repo_root/smoke" "$work/smoke"
rm -rf "$work/smoke/.dart_tool" "$work/smoke/pubspec.lock" "$work/smoke/test/goldens"
chmod -R a+rwX "$work/smoke"
run_smoke '
  flutter --version
  flutter pub get --offline
  flutter test --update-goldens
  flutter test
' --user 1001:1001 -e HOME=/tmp

echo "Smoke test passed for $image"

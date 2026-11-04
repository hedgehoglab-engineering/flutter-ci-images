#!/usr/bin/env bash
# Test tag-exists.sh with stub gh and curl executables.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/tag-exists.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$STUB_GH_MODE" in
  tag)       echo '[{"metadata":{"container":{"tags":["3.47.8","3.47.9"]}}}]' ;;
  notag)     echo '[{"metadata":{"container":{"tags":["3.47.8"]}}}]' ;;
  404)       echo '{"message":"Package not found.","documentation_url":"https://docs.github.com/rest/packages/packages#list-package-versions-for-a-package-owned-by-an-organization","status":"404"}'; echo 'gh: Package not found. (HTTP 404)' >&2; exit 1 ;;
  404empty)  echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  500)       echo 'gh: Server Error (HTTP 500)' >&2; exit 1 ;;
  partial404) echo '[{"metadata":{"container":{"tags":["3.47.9"]}}}]'; echo '{"message":"Package not found.","documentation_url":"https://docs.github.com/rest/packages/packages#list-package-versions-for-a-package-owned-by-an-organization","status":"404"}'; echo 'gh: Package not found. (HTTP 404)' >&2; exit 1 ;;
  malformed) echo 'not json' ;;
esac
STUB
cat >"$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s' "$STUB_CURL_CODE"
[ "$STUB_CURL_CODE" != "000" ] || exit 6
STUB
chmod +x "$tmp/bin/gh" "$tmp/bin/curl"

failures=0

# check <name> <gh mode> <registry code> <expected stdout or "FAIL">
check() {
  local name="$1" gh_mode="$2" code="$3" expected="$4" actual rc=0
  actual="$(PATH="$tmp/bin:$PATH" GH_TOKEN=test STUB_GH_MODE="$gh_mode" STUB_CURL_CODE="$code" \
    "$script" 3.47.9 2>/dev/null)" || rc=$?
  if [ "$expected" = "FAIL" ]; then
    if [ "$rc" -ne 0 ] && [ -z "$actual" ]; then
      echo "ok   $name"
    else
      echo "FAIL $name (rc=$rc, output='$actual')"
      failures=$((failures + 1))
    fi
  elif [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name (rc=$rc, output='$actual', expected '$expected')"
    failures=$((failures + 1))
  fi
}

check "API 404 + registry 403 -> false"      404       403 false
check "API 404 + registry 200 -> true"       404       200 true
check "API ok with tag -> true"              tag       404 true
check "API ok without tag + registry 404"    notag     404 false
check "API ok without tag + registry 500"    notag     500 FAIL
check "API 404 + registry 500 -> error"      404       500 FAIL
check "API 500 -> error"                     500       404 FAIL
check "API malformed JSON -> error"          malformed 404 FAIL
check "API 404 empty stdout + registry 403"  404empty  403 false
check "API partial page then 404 -> error"  partial404 403 FAIL
check "registry 000 -> error"                tag       000 FAIL

[ "$failures" -eq 0 ] || { echo "$failures test(s) failed" >&2; exit 1; }
echo "All tag-exists tests passed"

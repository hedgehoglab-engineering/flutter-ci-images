#!/usr/bin/env bash
# Print "true" or "false" for whether the image tag exists in GHCR.
# Fails closed: any ambiguous result exits non-zero without printing a verdict.
# Usage: tag-exists.sh <version>   (env: GH_TOKEN required; OWNER, PACKAGE optional)
#
# Two probes:
#   registry: HEAD https://ghcr.io/v2/<owner>/<package>/manifests/<version>
#   api:      gh api /orgs/<owner>/packages/container/<package>/versions
set -euo pipefail

OWNER="${OWNER:-hedgehoglab-engineering}"
PACKAGE="${PACKAGE:-flutter}"
: "${GH_TOKEN:?GH_TOKEN is required}"

[ $# -eq 1 ] || { echo "Usage: $0 <version>" >&2; exit 2; }
version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $version" >&2; exit 2; }

out="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$out" "$err"' EXIT

# Registry probe. curl prints 000 when the request itself fails.
registry_code="$(curl -sS -o /dev/null -w '%{http_code}' -I \
  -H "Authorization: Bearer $(printf %s "$GH_TOKEN" | base64 | tr -d '\n')" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  "https://ghcr.io/v2/${OWNER}/${PACKAGE}/manifests/${version}" 2>/dev/null)" || true

case "$registry_code" in
  200)
    echo true
    exit 0
    ;;
  404 | 401 | 403)
    : # the registry shows no manifest to this token
    ;;
  *)
    echo "Registry probe returned ambiguous status '${registry_code}'" >&2
    exit 1
    ;;
esac

# Packages API probe.
if gh api --paginate "/orgs/${OWNER}/packages/container/${PACKAGE}/versions" >"$out" 2>"$err"; then
  # --paginate emits one JSON array per page; slurp and flatten.
  if ! tags="$(jq -s -c '[.[][] | .metadata.container.tags[]?]' "$out" 2>/dev/null)"; then
    echo "Could not parse package versions response" >&2
    exit 1
  fi
  if jq -e --arg v "$version" 'index($v) != null' <<<"$tags" >/dev/null; then
    echo true
  else
    # Registry already returned 404/401/403, so both probes agree the tag is absent.
    echo false
  fi
  exit 0
fi

# A failed call yields a verdict only for a clean 404: stderr says HTTP 404 and
# stdout is either empty or exactly one error object with status "404" and no
# arrays (gh writes the API error body to stdout). Partial output from a failed
# paginated call is never trusted.
is_clean_404() {
  grep -q 'HTTP 404' "$err" || return 1
  [ ! -s "$out" ] && return 0
  jq -s -e '
    length == 1
    and (.[0] | type == "object")
    and (.[0].status | tostring) == "404"
    and (.[0] | [.. | arrays] | length == 0)' "$out" >/dev/null 2>&1
}

if is_clean_404; then
  echo "warning: package not visible to token; treating as first publish — a push without access will be rejected by GHCR, so no tag can be overwritten" >&2
  echo false
  exit 0
fi

echo "Could not determine tag state (registry ${registry_code}):" >&2
cat "$err" >&2
exit 1

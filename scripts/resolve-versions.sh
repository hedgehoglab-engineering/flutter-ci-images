#!/usr/bin/env bash
# Print a JSON array of {"version","revision"} for stable Flutter releases, ascending.
# Usage: resolve-versions.sh [--min X.Y.Z] | --version X.Y.Z
set -euo pipefail

FEED_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

min="3.47.8"
only=""

while [ $# -gt 0 ]; do
  case "$1" in
    --min)
      [ $# -ge 2 ] || { echo "--min needs a value" >&2; exit 2; }
      min="$2"
      shift 2
      ;;
    --version)
      [ $# -ge 2 ] || { echo "--version needs a value" >&2; exit 2; }
      only="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--min X.Y.Z] | --version X.Y.Z" >&2
      exit 2
      ;;
  esac
done

[[ "$min" =~ $SEMVER_RE ]] || { echo "Invalid --min: $min" >&2; exit 2; }
if [ -n "$only" ]; then
  [[ "$only" =~ $SEMVER_RE ]] || { echo "Invalid --version: $only" >&2; exit 2; }
fi

feed="$(curl -fsSL --retry 3 --retry-all-errors "$FEED_URL")"

# Unique stable "version<TAB>revision" lines, with strict semver versions only.
pairs="$(jq -r --arg re "$SEMVER_RE" '
  .releases[]
  | select(.channel == "stable")
  | select(.version | test($re))
  | "\(.version)\t\(.hash)"' <<<"$feed" | sort -u -t $'\t' -k1,1 | sort -V -t $'\t' -k1,1)"

if [ -n "$only" ]; then
  selected="$(awk -F '\t' -v v="$only" '$1 == v' <<<"$pairs")"
  if [ -z "$selected" ]; then
    echo "Version $only is not a stable release in the feed" >&2
    exit 1
  fi
else
  selected=""
  while IFS=$'\t' read -r version revision; do
    [ -n "$version" ] || continue
    # Keep versions >= min: min sorts first (or ties) in a version sort.
    if [ "$(printf '%s\n%s\n' "$min" "$version" | sort -V | head -n1)" = "$min" ]; then
      selected+="${version}"$'\t'"${revision}"$'\n'
    fi
  done <<<"$pairs"
fi

jq -R -s -c '
  split("\n") | map(select(length > 0) | split("\t") | {version: .[0], revision: .[1]})
' <<<"$selected"

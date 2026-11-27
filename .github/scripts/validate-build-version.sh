#!/usr/bin/env bash
set -euo pipefail

if [[ ! "${BUILD_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Build version must be X.Y.Z" >&2
  exit 1
fi
IFS='.' read -r major minor patch <<< "$BUILD_VERSION"
for part in "$major" "$minor" "$patch"; do
  if [[ "$part" =~ ^0[0-9]+$ ]] || (( ${#part} > 5 )) || (( 10#$part > 65535 )); then
    echo "Version components must be 0..65535 without leading zeros" >&2
    exit 1
  fi
done

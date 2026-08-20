#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

targets=(
    "windows 386" "windows amd64" "windows arm64"
    "linux 386" "linux amd64" "linux arm64"
    "darwin amd64" "darwin arm64"
)
for target in "${targets[@]}"; do
    # Intentional word splitting: every validated entry is exactly GOOS GOARCH.
    read -r goos goarch <<<"$target"
    "$repo_root/scripts/build-target.sh" "$goos" "$goarch"
done

"$repo_root/scripts/verify-matrix.sh"

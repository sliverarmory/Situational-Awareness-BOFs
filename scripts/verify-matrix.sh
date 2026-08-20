#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

portable_commands=()
while IFS= read -r command; do
    portable_commands+=("$command")
done < <(jq -er '.command_sets.portable[]' portable/manifest.json)
windows_commands=()
while IFS= read -r command; do
    windows_commands+=("$command")
done < <(find src/SA -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort)
windows_targets=(windows/386 windows/amd64 windows/arm64)
unix_targets=(linux/386 linux/amd64 linux/arm64 darwin/amd64 darwin/arm64)

failures=0
verify_artifact() {
    local target="$1"
    local command="$2"
    goos="${target%/*}"
    goarch="${target#*/}"
    artifact="dist/$target/$command.o"
    if [[ ! -s "$artifact" ]]; then
        echo "missing: $artifact" >&2
        failures=$((failures + 1))
        return
    fi
    description="$(file -b "$artifact")"
    case "$goos/$goarch" in
        windows/386) expected="80386 COFF" ;;
        windows/amd64) expected="amd64 COFF" ;;
        windows/arm64) expected="Aarch64 COFF" ;;
        linux/386) expected="ELF 32-bit LSB relocatable, Intel 80386" ;;
        linux/amd64|darwin/amd64) expected="ELF 64-bit LSB relocatable, x86-64" ;;
        linux/arm64|darwin/arm64) expected="ELF 64-bit LSB relocatable, ARM aarch64" ;;
    esac
    if [[ "$description" != *"$expected"* ]]; then
        echo "wrong format: $artifact: $description" >&2
        failures=$((failures + 1))
    fi
}

for target in "${windows_targets[@]}"; do
    for command in "${windows_commands[@]}"; do
        verify_artifact "$target" "$command"
    done
done
for target in "${unix_targets[@]}"; do
    for command in "${portable_commands[@]}"; do
        verify_artifact "$target" "$command"
    done
done

if (( failures != 0 )); then
    echo "matrix verification failed with $failures error(s)" >&2
    exit 1
fi

if ! diff -u \
    <(
        {
            for target in "${windows_targets[@]}"; do
                for command in "${windows_commands[@]}"; do
                    printf "dist/%s/%s.o\n" "$target" "$command"
                done
            done
            for target in "${unix_targets[@]}"; do
                for command in "${portable_commands[@]}"; do
                    printf "dist/%s/%s.o\n" "$target" "$command"
                done
            done
        } | LC_ALL=C sort
    ) \
    <(find dist -type f -name '*.o' | LC_ALL=C sort); then
    echo "dist does not contain the exact 317-object matrix" >&2
    exit 1
fi

if ! diff -u testdata/e2e-manifest.json <(node scripts/generate-e2e-manifest.mjs); then
    echo "e2e manifest is stale; regenerate it with scripts/generate-e2e-manifest.mjs --write" >&2
    exit 1
fi
if ! diff -u \
    <(find src/SA -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort) \
    <(jq -r '.command_sets.portable[], .command_sets["windows-only"][]' portable/manifest.json | LC_ALL=C sort -u); then
    echo "portable manifest does not classify every retained upstream command" >&2
    exit 1
fi

expected_count=$(( ${#windows_commands[@]} * ${#windows_targets[@]} + ${#portable_commands[@]} * ${#unix_targets[@]} ))
echo "verified $expected_count objects (all ${#windows_commands[@]} Windows commands plus ${#portable_commands[@]} portable commands)"

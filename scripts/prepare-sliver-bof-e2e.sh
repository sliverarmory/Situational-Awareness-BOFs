#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "${SLIVER_BOF_E2E_PHASE:-}" != plan ||
      -n "${SLIVER_BOF_E2E_TARGET:-}" ||
      -n "${SLIVER_BOF_E2E_OS:-}" ||
      -n "${SLIVER_BOF_E2E_ARCH:-}" ]]; then
    echo "error: Sliver BOF E2E preparation must run in the plan phase" >&2
    exit 2
fi
if [[ -z "${RUNNER_TEMP:-}" || "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo "error: the Sliver BOF E2E planner requires Linux x86_64 and RUNNER_TEMP" >&2
    exit 2
fi

for tool in curl file jq node sha256sum tar; do
    command -v "$tool" >/dev/null || { echo "error: missing $tool" >&2; exit 1; }
done

zig_version=0.14.0
zig_sha256=473ec26806133cf4d1918caf1a410f8403a13d979726a9045b421b685031a982
zig_root="${RUNNER_TEMP}/situational-awareness-zig-${zig_version}"
zig_archive="${RUNNER_TEMP}/zig-linux-x86_64-${zig_version}.tar.xz"

if [[ ! -x "$zig_root/zig" ]]; then
    mkdir -p "$zig_root"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
        --output "$zig_archive" \
        "https://ziglang.org/download/${zig_version}/zig-linux-x86_64-${zig_version}.tar.xz"
    printf '%s  %s\n' "$zig_sha256" "$zig_archive" | sha256sum --check --strict
    tar -xJf "$zig_archive" -C "$zig_root" --strip-components=1
fi
if [[ "$("$zig_root/zig" version)" != "$zig_version" ]]; then
    echo "error: expected Zig $zig_version" >&2
    exit 1
fi

llvm_objdump="$(command -v llvm-objdump-18 || command -v llvm-objdump || true)"
if [[ -z "$llvm_objdump" ]]; then
    for tool in sudo apt-get; do
        command -v "$tool" >/dev/null || { echo "error: missing $tool to install LLVM objdump" >&2; exit 1; }
    done
    sudo apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends llvm
    llvm_objdump="$(command -v llvm-objdump-18 || command -v llvm-objdump || true)"
fi
if [[ -z "$llvm_objdump" ]]; then
    echo "error: LLVM objdump is required for Darwin/arm64 verification" >&2
    exit 1
fi

export ZIG="$zig_root/zig"
export OBJDUMP="$llvm_objdump"
export ZIG_GLOBAL_CACHE_DIR="${RUNNER_TEMP}/situational-awareness-zig-cache/global"
export ZIG_LOCAL_CACHE_DIR="${RUNNER_TEMP}/situational-awareness-zig-cache/local"

node scripts/generate-sliver-bof-e2e.mjs --check
./scripts/build-matrix.sh

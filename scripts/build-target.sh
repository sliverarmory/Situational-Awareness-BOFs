#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 <goos> <goarch>" >&2
    exit 2
fi
goos="$1"
goarch="$2"
target_cflag=

case "$goos/$goarch" in
    windows/386) zig_target=x86-windows-gnu; object_pattern="80386 COFF" ;;
    windows/amd64) zig_target=x86_64-windows-gnu; object_pattern="amd64 COFF" ;;
    windows/arm64) zig_target=aarch64-windows-gnu; object_pattern="Aarch64 COFF" ;;
    linux/386) zig_target=x86-linux-none; platform_define=BOF_LINUX; object_pattern="ELF 32-bit LSB relocatable, Intel 80386" ;;
    linux/amd64) zig_target=x86_64-linux-none; platform_define=BOF_LINUX; object_pattern="ELF 64-bit LSB relocatable, x86-64" ;;
    linux/arm64) zig_target=aarch64-linux-none; platform_define=BOF_LINUX; object_pattern="ELF 64-bit LSB relocatable, ARM aarch64" ;;
    darwin/amd64) zig_target=x86_64-linux-none; platform_define=BOF_DARWIN; object_pattern="ELF 64-bit LSB relocatable, x86-64" ;;
    darwin/arm64) zig_target=aarch64-linux-none; platform_define=BOF_DARWIN; object_pattern="ELF 64-bit LSB relocatable, ARM aarch64"; target_cflag=-mcpu=baseline+reserve_x18 ;;
    *) echo "error: unsupported target $goos/$goarch" >&2; exit 2 ;;
esac

zig_bin="${ZIG:-zig}"
if ! command -v "$zig_bin" >/dev/null 2>&1; then
    echo "error: Zig is required (set ZIG=/path/to/zig)" >&2
    exit 1
fi

cache_root="${TMPDIR:-/tmp}/situational-awareness-bofs-zig"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$cache_root/global}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$cache_root/local}"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "dist/$goos/$goarch"

portable_commands=()
while IFS= read -r command; do
    portable_commands+=("$command")
done < <(jq -er '.command_sets.portable[]' portable/manifest.json)
windows_commands=()
while IFS= read -r command; do
    windows_commands+=("$command")
done < <(find src/SA -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort)
if [[ "${#windows_commands[@]}" -ne 64 ]]; then
    echo "error: expected 64 retained upstream Windows commands, found ${#windows_commands[@]}" >&2
    exit 1
fi

command_configuration() {
    case "$1" in
        arp) echo BOF_COMMAND_ARP portable/src/portable.c ;;
        cacls) echo BOF_COMMAND_CACLS portable/src/posix.c ;;
        dir) echo BOF_COMMAND_DIR portable/src/portable.c ;;
        enumLocalSessions) echo BOF_COMMAND_ENUM_LOCAL_SESSIONS portable/src/posix.c ;;
        env) echo BOF_COMMAND_ENV portable/src/portable.c ;;
        findLoadedModule) echo BOF_COMMAND_FIND_LOADED_MODULE portable/src/posix.c ;;
        ipconfig) echo BOF_COMMAND_IPCONFIG portable/src/portable.c ;;
        listmods) echo BOF_COMMAND_LISTMODS portable/src/posix.c ;;
        locale) echo BOF_COMMAND_LOCALE portable/src/portable.c ;;
        md5) echo BOF_COMMAND_MD5 portable/src/portable.c ;;
        netlocalgroup) echo BOF_COMMAND_NETLOCALGROUP portable/src/posix.c ;;
        netloggedon) echo BOF_COMMAND_NETLOGGEDON portable/src/posix.c ;;
        netloggedon2) echo BOF_COMMAND_NETLOGGEDON2 portable/src/posix.c ;;
        netstat) echo BOF_COMMAND_NETSTAT portable/src/portable.c ;;
        netuser) echo BOF_COMMAND_NETUSER portable/src/posix.c ;;
        netuserenum) echo BOF_COMMAND_NETUSERENUM portable/src/posix.c ;;
        nslookup) echo BOF_COMMAND_NSLOOKUP portable/src/portable.c ;;
        probe) echo BOF_COMMAND_PROBE portable/src/portable.c ;;
        resources) echo BOF_COMMAND_RESOURCES portable/src/portable.c ;;
        routeprint) echo BOF_COMMAND_ROUTEPRINT portable/src/portable.c ;;
        sha1) echo BOF_COMMAND_SHA1 portable/src/portable.c ;;
        sha256) echo BOF_COMMAND_SHA256 portable/src/portable.c ;;
        tasklist) echo BOF_COMMAND_TASKLIST portable/src/portable.c ;;
        uptime) echo BOF_COMMAND_UPTIME portable/src/portable.c ;;
        whoami) echo BOF_COMMAND_WHOAMI portable/src/portable.c ;;
        *) echo "error: unknown portable command $1" >&2; return 1 ;;
    esac
}

if [[ "$goos" == windows ]]; then
    commands=("${windows_commands[@]}")
    for command in "${commands[@]}"; do
        echo "CC  $goos/$goarch $command (retained Windows source)"
        "$zig_bin" cc -target "$zig_target" -Os \
            -fno-unwind-tables -fno-asynchronous-unwind-tables \
            -Wno-missing-prototype-for-cc -Wno-ignored-attributes \
            -Isrc/common -DBOF -c "src/SA/$command/entry.c" \
            -o "dist/$goos/$goarch/$command.o"
    done
else
    commands=("${portable_commands[@]}")
    for command in "${commands[@]}"; do
        read -r define source_file <<<"$(command_configuration "$command")"
        echo "CC  $goos/$goarch $command"
        "$zig_bin" cc -target "$zig_target" -std=c11 -Os \
            ${target_cflag:+"$target_cflag"} \
            -ffreestanding -fno-builtin -fno-stack-protector -fPIC \
            -fno-unwind-tables -fno-asynchronous-unwind-tables \
            -Werror=implicit-function-declaration -Wno-unused-function \
            -Iportable/include -DBOF -D"$platform_define" -D"$define" \
            -c "$source_file" -o "dist/$goos/$goarch/$command.o"
    done
fi

for command in "${commands[@]}"; do
    artifact="dist/$goos/$goarch/$command.o"
    description="$(file -b "$artifact")"
    if [[ "$description" != *"$object_pattern"* ]]; then
        echo "wrong format: $artifact: $description" >&2
        exit 1
    fi
done

if [[ "$goos/$goarch" == darwin/arm64 ]]; then
    objdump_bin="${OBJDUMP:-objdump}"
    if ! command -v "$objdump_bin" >/dev/null 2>&1; then
        echo "error: objdump is required to verify Darwin/arm64 register use (set OBJDUMP=/path/to/llvm-objdump)" >&2
        exit 1
    fi
    for command in "${commands[@]}"; do
        artifact="dist/$goos/$goarch/$command.o"
        if ! disassembly="$("$objdump_bin" -d "$artifact")"; then
            echo "error: cannot disassemble $artifact with $objdump_bin" >&2
            exit 1
        fi
        if grep -Eq '(^|[^[:alnum:]_])([wx]18)([^[:alnum:]_]|$)' <<<"$disassembly"; then
            echo "error: Darwin/arm64 artifact uses Apple's reserved x18 register: $artifact" >&2
            exit 1
        fi
    done
fi

if ! diff -u \
    <(for command in "${commands[@]}"; do printf "dist/%s/%s/%s.o\n" "$goos" "$goarch" "$command"; done | LC_ALL=C sort) \
    <(find "dist/$goos/$goarch" -maxdepth 1 -type f -name '*.o' | LC_ALL=C sort); then
    echo "error: dist/$goos/$goarch does not contain the exact target artifact set" >&2
    exit 1
fi
if ! diff -u \
    <(for command in "${commands[@]}"; do printf "dist/%s/%s/%s.o\n" "$goos" "$goarch" "$command"; done | LC_ALL=C sort) \
    <(jq -r --arg os "$goos" --arg arch "$goarch" '.artifacts[] | select(.os == $os and .arch == $arch) | .path' testdata/e2e-manifest.json | LC_ALL=C sort); then
    echo "error: e2e manifest does not exactly cover $goos/$goarch" >&2
    exit 1
fi

echo "verified $goos/$goarch (${#commands[@]} objects)"

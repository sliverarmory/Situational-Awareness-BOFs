# Cross-platform BOF provenance

This branch started from commit `40786cff3c0ac39cb42d64187d3b69efb19acac9`
of TrustedSec's `CS-Situational-Awareness-BOF` repository as mirrored by the
Sliver Armory. The complete Windows source set under `src/` and its GPL-2.0
license are retained. The portable Unix implementation and matrix metadata are
additive files under `portable/`.

Calling-convention declarations were corrected for 32-bit Windows ABI compatibility:
`MSVCRT$malloc` is declared `__cdecl`, while `KERNEL32$GlobalAlloc`,
`KERNEL32$GlobalFree`, and the zero-argument `KERNEL32$GetCurrentProcessId`
use `WINAPI`. These declarations match the calling conventions of the system
exports and prevent double or missing caller stack cleanup on 386.

## Command coverage

All 64 upstream commands build as native Windows COFF objects for 386, amd64,
and arm64. The portable Unix set is `arp`, `cacls`, `dir`,
`enumLocalSessions`, `env`, `findLoadedModule`, `ipconfig`, `listmods`,
`locale`, `md5`, `netlocalgroup`, `netloggedon`, `netloggedon2`, `netstat`,
`netuser`, `netuserenum`, `nslookup`, `probe`, `resources`, `routeprint`,
`sha1`, `sha256`, `tasklist`, `uptime`, and `whoami`. Commands tied to Windows-only subsystems
(Active Directory, COM, DPAPI, Registry, SCM, scheduled tasks, WMI, and similar
APIs) remain present and tested on Windows but are not mislabeled as portable.

Linux objects are native ELF `ET_REL` objects. Darwin objects also use an ELF
relocatable container, compiled without Linux headers or a Linux libc; the
machine code uses the shared SysV AMD64 or AAPCS64 calling convention and
imports only Darwin ABI symbols selected by `BOF_DARWIN`. This is an explicit
Reflektor interchange format, not a claim that macOS natively links ELF files.
Darwin/arm64 builds enable Zig's `reserve_x18` target feature so Linux-targeted
code generation never uses Apple's reserved platform register. Portable Darwin BOFs also use the
non-variadic `BeaconOutput` callback, avoiding the Apple/Linux variadic ABI
difference.

The Unix implementation is freestanding: it does not include host SDK headers
and keeps hashing code inside each object. Its external surface is limited to
the Beacon argument/output callbacks plus small, stable POSIX or Darwin libc
APIs. `dir` reports names only, avoiding target-specific stat layouts.

## Build and verify

Zig, Node.js, `jq`, `file`, `objdump` (or `OBJDUMP=/path/to/llvm-objdump`),
and Bash are the build-time dependencies:

```sh
make matrix
```

This produces and verifies 317 objects: 192 objects for the complete Windows
corpus and 125 objects for the 25 portable commands on the five Unix targets.
The exact target matrix is in `portable/manifest.json`. The explicit
artifact-by-artifact execution contract is `testdata/e2e-manifest.json`; its
generator also checks that no upstream Windows command silently disappears.

The build uses temporary Zig caches so no toolchain cache is written into the
repository. Artifacts are written under `dist/<goos>/<goarch>/` and are ignored
by Git.

CI runtime rows should build only their host artifact set:

```sh
./scripts/build-target.sh "$(go env GOOS)" "$(go env GOARCH)"
```

The command accepts only the same eight explicit Reflektor targets and verifies
that the selected `dist/<goos>/<goarch>` directory and E2E manifest contain the
exact expected set (64 Windows objects or 25 Unix objects). Reflektor then
runs its tagged corpus test with `go test -tags bof ./integration`.

## POSIX mappings for Windows-oriented commands

The following ports preserve the upstream packed argument shape but define a
local Unix meaning. Unsupported remote, domain, cross-process, wildcard, and
Windows account-state modes are rejected explicitly instead of being ignored.

| Command | Unix behavior | Deliberate limitation |
| --- | --- | --- |
| `cacls` | Reports `access(2)` existence and real-UID/GID read, write, and execute/search results for one UTF-16 path. | It does not enumerate ACL entries, ownership, mode bits, or wildcards. |
| `enumLocalSessions` | Lists local login records from the base-system `/usr/bin/who` utility. | Local host only. |
| `findLoadedModule` | Case-insensitively searches the current process's `/proc/self/maps` paths on Linux or dyld images on Darwin; the optional process filter must match the current process. | Cross-process search is not exposed. |
| `listmods` | Lists modules for PID `0` or the current PID using procfs or dyld. | Any other PID is rejected. |
| `netlocalgroup` | Operation `0` enumerates the POSIX group database; operation `1` lists members of one group. | A non-empty server/domain selector is rejected. |
| `netloggedon` | Lists local login records in compact form using `/usr/bin/who`. | A non-empty remote computer is rejected. |
| `netloggedon2` | Lists the same local records with structured per-session delimiters. | A non-empty remote computer is rejected. |
| `netuser` | Looks up one POSIX account; an empty username selects the effective user. | A non-empty domain/server is rejected. |
| `netuserenum` | Enumerates the POSIX account database when `use_domain=0` and `filter=1`. | Domain mode and Windows locked/disabled account filters are rejected. |

## Runtime limitations

- BOFs execute in-process and inherit the privileges and filesystem view of
  the host process.
- Unix `dir` is intentionally non-recursive. The second packed argument is
  retained for compatibility with the original Windows command.
- Linux 386 uses the glibc-compatible `dirent` ABI used by the current
  Reflektor test image.
- Darwin `arp` invokes the bounded system command `/usr/sbin/arp -an`; Linux
  reads `/proc/net/arp` directly.
- Unix `nslookup` uses the host resolver and supports A, AAAA, and ANY address
  lookups; selecting a custom DNS server remains Windows-only.
- Unix `probe` bounds TCP connection attempts with one monotonic deadline after
  hostname resolution. Linux uses nonblocking `poll`; Darwin uses the public
  TCP connection-timeout socket option. Resolver latency is outside that
  connection deadline.
- Linux network, route, resource, and process enumeration reads procfs where
  available. Darwin uses the platform `netstat`, `vm_stat`, `df`, and `ps`
  utilities at fixed system paths. The Darwin `netstat` port reports all socket
  families and includes the requested Windows-compatible filter value.
- Darwin ELF objects are for Reflektor's loader only; system linkers and
  `dlopen` do not consume them.

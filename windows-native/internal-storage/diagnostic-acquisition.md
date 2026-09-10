# A1625 reference acquisition without an existing tvOS shell

2026-09-09: the owner confirmed that no existing tvOS SSH/diagnostic environment
or previously collected IORegistry/disk0 reference data is available. The next
work is to evaluate a temporary diagnostic RAM disk. Nothing in this document
is an approved device boot recipe; no candidate has been transferred or booted.

## Candidate and static findings

The public [SSHRD_Script](https://github.com/verygenericname/SSHRD_Script/tree/d99ec4a19172b87d80fd9dea25eabf39291425a0)
contains Apple TV payload selection, but its documented hosts are macOS/Linux.
Its T7000 boot arguments include `nand-enable-reformat=1 -restore`. It also
has an explicit erase command. **Do not run the stock script for this issue.**
Removing a flag alone would not establish read-only behavior; the complete
ramdisk startup and firmware compatibility must be checked.

Pinned research inputs (stored privately as local research artifacts):

| Input | Revision / SHA256 |
| --- | --- |
| SSHRD_Script revision | d99ec4a19172b87d80fd9dea25eabf39291425a0 |
| sshrd.sh SHA256 | e15b45d4e8465e0116313a63442750e6d18d2af776667cec894ee8ac54fb807d |
| sshtars submodule revision | 6c05c8a74095c63e1d130ecbf309d77efa6d17d5 |
| atvssh.tar.gz SHA256 | 9c9a9988272adfd0b7cce0cbee716c147cb2ccd9eaadd627a75c2f9f2dc8af55 |

The owner also confirmed that the installed tvOS version is unknown. Do not
reboot the current RAM Linux merely to obtain a version from Settings.

Static inspection of that archive found ARM64 Mach-O `restored_external`,
`dropbear`, `ioreg` and `bash` binaries whose LC_BUILD_VERSION platform is 3
(tvOS), with minimum OS 12.0.0.
This supports platform selection, but is not A1625 boot validation. The archive
also contains a `mount_filesystems` helper with APFS mount commands lacking
read-only options. That helper must not be invoked or included in an automatic
acquisition flow. The replacement restore daemon's inspected `_main` path
initializes USB and watchdog handling, then invokes its inetd loop with
`micro_inetd 22 /usr/local/bin/dropbear -i`. The loop accepts a connection and
executes that fixed Dropbear command. The archive profile contains shell
environment settings, not an automatic mount command. These findings do not
establish that the base Apple RAM disk or kernel avoids storage writes; their
startup paths still need inspection. The archive includes shared SSH host
keys, which must not be treated as a private device identity.

Native Windows `irecovery` 1.2.1 and `iproxy` (libusbmuxd 2.1.1) are now
extracted under `artifacts/diagnostic-ramdisk-research/windows-tools/extracted`.
Six MSYS2 UCRT64 packages were downloaded and checked against SHA256 values
from the local pacman repository database; this is checksum verification,
not an independent package-signature verification. Their exact URLs and hashes
are in `diagnostic-tools.lock.json`. No global packages or drivers were changed.
Both executables successfully printed help using the existing MSYS2 UCRT64
runtime on PATH. `irecovery --devices` (its built-in table, not a USB query)
includes `AppleTV5,3 j42dap 0x34 0x7000`. No device connection was attempted.
The existing runtime dependencies are not yet bundled or locked; this is not
yet a standalone redistributable toolchain. Native img4tool, iBoot64Patcher and
hfsplus editing was subsequently resolved below; native iBoot patching and a
compatible audited base RAM disk remain unresolved.

## Apple base RAM disk static inspection

The existing native Windows `ipsw` 3.1.713 tool can extract the IM4P payload;
an additional img4tool binary is not required for this extraction step.
The Apple-hosted 12.4 / 16M568 IPSW referenced in
`artifacts/wifi-research/tvos-12.4-provenance.json` yielded a BuildManifest with
only `AppleTV5,3`, chip `0x7000`, board `0x34`, device class `j42dap`.
Its two identities explicitly differ: erase uses `048-79244-073.dmg`, update
uses `048-79267-073.dmg`. Index zero must not be blindly selected.

The **update** image was downloaded for offline inspection only. Its SHA1
matches the manifest Digest `f6fdf2ed47c47f1043e0faa13da305c8150201e4`.
Local SHA256 values are:

| Artifact | SHA256 |
| --- | --- |
| BuildManifest.plist | 6357c3247b2978498b4e7f757f8891f5260fd0a1d8d290d00ff2f0cbbd3da5ef |
| 048-79267-073.dmg (IM4P) | 226c37c4c519093fada72214b8113165f669aa651659234a8957ee678350d64e |
| Extracted payload | b65d8d8ebea6f027ff9fc34ffba9671ca52373a76e529c186a0562469270d75c |

The payload is a 68,165,632-byte HFSX volume (`HX` at offset 1024), not a
UDIF wrapper. `ipsw disk hfs` rejects it; native 7-Zip 26.00 successfully lists
and extracts its startup files without mounting it. No image bytes were
patched to bypass the parser. Its four LaunchDaemons are:

- `com.apple.restored_update`: RunAtLoad executes `/usr/local/bin/restored_update`.
- `com.apple.PurpleReverseProxy.ramdisk`: socket-activated restore proxy.
- `com.apple.ReportCrash.restored`: exception service with restore log path.
- `com.apple.syslogd`: system logging service.

Only group and account databases occur under `private/etc` in this image.
This identifies the actual restore entry point that a diagnostic candidate
must replace or exclude. **The original update RAM disk must not be booted.**
The word “update” does not imply read-only behavior. The stock restore daemon,
kernel storage initialization and final modified image remain unaudited, and
12.4 compatibility with the unknown installed firmware is not established.

### Native HFSX editing test

`build-hfsplus.sh` builds only the HFS utility and common library from
[planetbeing/xpwn revision 20c32e5](https://github.com/planetbeing/xpwn/tree/20c32e5c12d1b22a9d55a59a0ff6267f539b77f4),
using MSYS2 UCRT64 GCC 16.1.0 and zlib. Source archive SHA256 is
`633a34c602bc95c27342eb63ac2502a15f7394ad8dcc9ace1781ba4bb2fb6e0d`.
The script expects that archive under the research artifacts directory and
does not download or access any device. It omits the unrelated firmware tools.
Upstream emits packed-member alignment warnings in catalog comparison;
this executable is an x86-64 host utility, not an ARM device binary.

On a disposable `hfs-tool-test.dmg` copy, listing and extracting the restored
plist succeeded. The extracted file SHA256 matched independent 7-Zip output
(`36f761c620265abeda2487911ad21720abdadda2b0b6c969601679fc43673e96`), and the image hash remained unchanged after those
read commands. Deleting just the restored launch plist from that copy then
succeeded; 7-Zip independently listed the remaining three plists. This is
an editor smoke test only, not a finished boot image or validation of all
HFS metadata edits. The original extracted payload remains unchanged.

### Minimal overlay and editor limitation

`prepare-diagnostic-overlay.py` now creates a deterministic inspection tar
containing exactly seven regular files: sh, dd, ioreg, restored_external,
dropbear, dropbearkey and libncurses.5.4.dylib. It checks the pinned input
archive hash and rejects missing, duplicate or non-regular selected entries.
Output SHA256 is `8abc621e6bc1791cb8a15326d4388d226478216751753653495de2e5375230ba`.
It contains no shared host keys, mount helper or automatic startup setting.
It is **not boot-ready**, and the preparation script never modifies an image.

Mach-O load commands for these files refer to libSystem, libz, libiconv,
CoreFoundation, IOKit and ncurses. The base image listing contains all of those
except ncurses, which is included in the overlay. This is a path-level check;
exported-symbol and ABI compatibility remain unverified.

The pinned xpwn CLI does **not** implement `untar`, despite having an internal
library helper with that name. An attempted `untar` on a disposable image did
nothing and returned zero. Therefore an exit code alone is insufficient.
The supported `add` command successfully inserted Dropbear in a separate
inspection copy; extraction reproduced its original bytes and SHA256
`412ee2041841fa5b6dc41ee44366bbba48405b8d38e0291298d9ca14d54cccb4`.
Future image assembly must use individually verified edits, not copy the
SSHRD script's `untar` invocation. The inspection copy still has original
restore startup settings and must never be transferred or booted.

### Named import compatibility

`inspect-overlay-symbols.py` checks the overlay Mach-O bind and lazy-bind
tables against the extracted 16M568 library export tries. It follows explicit
library reexports and verifies individual symbol aliases against their target
library (for example libc `_memcpy` to libsystem_platform
`__platform_memmove`). All 671 named bind entries across the seven files
resolved. Per-file counts are 36 (dd), 195 (sh), 91 (ncurses), 127 (dropbear),
57 (dropbearkey), 42 (restored_external), and 123 (ioreg).

The report is `artifacts/diagnostic-ramdisk-research/overlay-symbol-report.json`.
Inputs are the previously pinned overlay and base image. Library extraction
by 7-Zip skipped an unrelated `libextension.dylib` relative symlink and returned
an error for that entry; none of the checked imports needed it. The extraction
must not be described as fully successful. No attempt was made to bypass its
link-path protection.

This check does not execute dyld, verify every transitive library import,
validate ABI behavior or assess kernel/IOP initialization. It establishes
named-symbol availability only. Installed-firmware compatibility and absence
of storage writes during startup remain unresolved.

Further [kernel analysis](tvos-readonly-analysis.md) verified a real
`nand-readonly` predicate, but also found RAM-root exceptions in two callers.
Adding `nand-readonly=1` to `rd=md0` is therefore insufficient as a universal
write guard. This is a concrete unresolved kernel condition, not merely an
unknown boot-argument spelling.

## Prerequisites for a concrete read-only candidate

1. Identify an AppleTV5,3/J42d firmware BuildIdentity and the installed firmware
   compatibility requirements. The older tvOS 12.4 kernelcache already on the
   host is a static research input, not evidence of the installed tvOS version.
2. Audit or replace the RAM startup program so it starts only the necessary
   USB transport and shell, with no automatic internal mounts, restore service,
   filesystem repairs, NVRAM changes or storage-formatting options.
3. Assemble the exact model's iBSS/iBEC/DeviceTree/kernel/RAM disk offline using
   verified native Windows tools. Lock all inputs, patches, outputs and boot
   arguments. Do not invoke generic scripts that mix build and device actions.
4. Inspect the finished RAM disk and actual boot commands before any transfer.
   Account for required firmware initialization; do not claim that RAM root
   alone proves absence of internal-storage writes.
5. Only after the boot prerequisites are established, arrange a fresh DFU
   session and execute one verified temporary stage at a time. Acquire only
   the A1625 service inventory, geometry, GPT and bounded sector hashes.

The user's answer resolves the previous access question. Do not ask again for
the same nonexistent environment. The overall issue remains incomplete while
this alternative acquisition path is investigated.

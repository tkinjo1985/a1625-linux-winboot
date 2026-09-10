# ANS power prerequisites snapshot

This diagnostic makes exactly two PMGR status reads: ANS at offset 0x20318
and DEBUG at offset 0x20118. Both offsets were resolved from the owned A1625
ADT and matched to the pinned T7000 power-domain nodes. It checks J42d/T7000
root compatibles and the exact PMGR resource before reading.

It does not access ANS registers, consume mailbox FIFO entries, send messages,
toggle power, reset a controller, map firmware or read/write NAND. The status
is only a snapshot; it cannot be used as a guarantee that a gate stays on.

Build using the repository's native Windows MSYS2 installation:

```powershell
& "$env:USERPROFILE/scoop/apps/msys2/current/usr/bin/bash.exe" windows-native/internal-storage/probe/build.sh
```

Outputs go to ignored `artifacts/ans-power-snapshot/`. The build script uses
the prepared native kernel tree and its vmlinux.symvers, checks 4 KiB pages,
and rebuilds the existing single-syscall runner. It does not deploy anything.

## Deployment prerequisites

Compare live `/sys/kernel/notes` with the exact local kernel ELF Build ID.
Use matching source, configuration, generated headers and symbol versions.
Do not load a module solely because its release string says `7.2.0`.
Transfer through verified SSH only to tmpfs, compare SHA256, and invoke the
existing `run_probe_once` with the module's absolute RAM path. Do not use
BusyBox insmod: its fallback can run a failing module initialization twice.
This module deliberately returns ECANCELED after successful reads to release
itself even when CONFIG_MODULE_UNLOAD is disabled. The runner's exit code
alone is not proof: require one new completion log, absence from proc/modules,
and continued USB/SSH availability. Any other return stops the stage.

## Build-only result, 2026-09-09

Native Windows compilation succeeded. The first candidate module SHA256 was
`84544eeabe3b17317f253ed01b65e2634799056e058c747eecf4663f8e8b198a`;
the runner SHA256 was
`880e89876ed9b860964705ec4cbf2b73421fd57c967b4e1069cf5c26c86e98a1`.
MODPOST reported missing conventional Module.symvers; the build explicitly
provided vmlinux.symvers through KBUILD_EXTRA_SYMBOLS and reported no unresolved
symbols. This is a compile result, not runtime validation.

**Not deployed:** the native build tree's ELF Build ID was
`3848d1b6e0bfa0c4c7abca7a9c9e8cfb33e754a2`, but the live device reported
`4776c5754ce5ac725ac272d841f0a7dee2c4156a`. Transfer/loading stopped before
any module execution. An archived ELF under
`artifacts/wifi-kernel-config/base-before-wifi-build/` matches the live Build ID
and has its configuration and symbol table; matching generated build headers
still need to be prepared before a valid live-baseline candidate can be built.
The Wi-Fi build tree must not be overwritten to do this.

## Matched baseline build and live result, 2026-09-09

The mismatch above was resolved without rebooting or replacing the Wi-Fi
build tree. The pinned kernel was exported into a separate
`artifacts/ans-baseline-kernel` tree. Use `git -c core.autocrlf=false archive`
when reproducing the export: Windows CRLF conversion breaks Kconfig parsing.
The archived baseline's ELF, configuration, symbols, System.map and Image
all matched their recorded SHA256 values. The baseline ELF matched a fresh
live Build ID check. The device does not expose `/proc/config.gz`.

After copying the archived `.config` and `vmlinux.symvers` (as Module.symvers)
into that isolated source tree, run:

```powershell
& "$env:USERPROFILE/scoop/apps/msys2/current/usr/bin/bash.exe" windows-native/internal-storage/probe/prepare-baseline.sh
& "$env:USERPROFILE/scoop/apps/msys2/current/usr/bin/bash.exe" -c 'ANS_KERNEL_TREE="$PWD/artifacts/ans-baseline-kernel" /usr/bin/bash windows-native/internal-storage/probe/build.sh'
```

`modules_prepare` completed and produced **no semantic configuration changes**
relative to the archived baseline. The module build completed with no MODPOST
missing-symbol warnings. Native host-tool link creation uses a PowerShell
helper restricted to the two isolated build directories.

Source review also identified that the resource-managing syscon lookup can
deassert resets when creating a map. The final diagnostic instead uses the
non-resource-managing lookup and rejects clock/reset/hardware-lock properties.
It imports `regmap_read` and no register-write or power-transition API.

The final module SHA256 is
`caff5de56840395c7fbb291559369a950cb96c9edb65844fbaf2eaea9f0a8aea`.
The runner hash remains `880e89876ed9b860964705ec4cbf2b73421fd57c967b4e1069cf5c26c86e98a1`.
See `baseline-build.lock.json` for source/config/header/artifact hashes.

Both artifacts were transferred to verified `/run` tmpfs over strict-host-key
SSH, and the remote hashes matched. An exclusive `attempted` directory guards
against rerunning this session's diagnostic. The runner made one finit_module
call and returned success for ECANCELED. There was exactly one completion log:

```text
ans=0f000200 target=0 actual=0 debug=00000200 target=0 actual=0
complete; two PMGR reads; no writes or ANS access
```

Both gates report OFF in their actual and target fields. The module was absent
from `/proc/modules` afterwards, ttyGS0 remained present, usb0 was up, SSH
returned successfully, and `/proc/partitions` still contained only zram0.
The expected out-of-tree kernel taint affects this RAM boot. This does not
prove FIFO/RTBuddy availability, NAND readability or repeated cold-boot safety.

Do not read ANS MMIO while these gates are off. The next probe needs verified
power-domain ownership, a bounded transition and rollback before any ANS access;
it must not use this old snapshot as evidence that a gate is currently active.
Power ownership alone is insufficient: the [completion audit](../completion-audit.md)
also identifies the unverified IOP stop/resume state. Do not add automatic
power-on based solely on this successful PMGR read.

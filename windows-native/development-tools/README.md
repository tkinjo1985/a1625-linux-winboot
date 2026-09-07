# A1625 RAM development tools

This directory builds a hash-verified, temporary Alpine v3.23 AArch64 package
bundle on Windows. SSH controls installation over the private USB NCM link;
a temporary HTTP server bound to `172.16.42.2` serves only public package assets.
It never invokes an on-device package manager and never mounts or writes Apple
TV storage. The Apple TV verifies the bundle and every APK before extracting
the APKs into `/run/a1625-tools/root`; package symlinks and permissions are
therefore handled by its Linux tar implementation. The base initramfs already
has BusyBox `ntpd`; this layer adds Git,
the Mozilla CA bundle, the OpenSSH client, and (for `development`) the
compiler, linker, `make`, `file`, `patch`, and `pkgconf` dependency closure.

Prepare the layer without a connected device:

```powershell
& .\windows-native\development-tools\Install-A1625DevelopmentTools.ps1 -Profile minimal -PrepareOnly
```

The resulting `artifacts\development-tools\alpine-v3.23-aarch64\<profile>\manifest.json`
records the pinned APKINDEX hash, every downloaded APK hash, and the transfer
bundle hash. Expected package hashes are checked against the committed
`packages.lock.json`, originally obtained from the official Alpine HTTPS
repository. Cached mismatches stop the build. `bundleSha256` is reproducible
across rebuilds and identifies the exact package, wrapper, and zram assets for
RAM-state compatibility. The Python builder also rejects unsafe APK paths,
special nodes, and entries beneath archive links. A deployment rechecks the bundle hash on the Apple TV before it
extracts it into RAM. Use a per-boot `known_hosts` file made by the RAM boot
restorer:

```powershell
& .\windows-native\development-tools\Install-A1625DevelopmentTools.ps1 `
  -Profile development -KnownHostsPath $knownHosts -EnableZram
```

`-EnableZram` is deliberately opt-in. It configures one 768 MiB `/dev/zram0`
swap area at priority 100 using the kernel's zstd compressor, with a 256 MiB
compressed-allocation limit. It refuses a
non-AArch64 system, an unavailable zstd backend, or any preconfigured zram
writeback. It does not set `backing_dev`; zram data remains RAM-only. Leave at
least one interactive USB ACM or SSH session available while testing pressure.

The deployment sets `HOME` and `GIT_CONFIG_GLOBAL` to `/run/codex-home` and
uses `/run/work`, so Git configuration and Codex's work directory follow the
same Windows-backed RAM-session state boundary. It writes only the non-secret
layer identity to `/run/a1625-development-layer.json`.

To repeat hardware verification, run a real HTTPS `git clone`/`fetch`,
confirm `swapon` survives a memory-pressure test while SSH and USB ACM remain
responsive, and record the emitted bundle byte size plus `free -m` and
`/proc/swaps` output. Results obtained on the owned A1625 are recorded in
[the validation report](../VALIDATION-ISSUES-3-4.md).

`verify-development.sh` checks the actual C/C++ compiler, linker, standard
libraries, SSH client, and other tools. `zram-pageout-check.c` uses 128 MiB
and `MADV_PAGEOUT` to verify swap round-trip integrity while checking SSH/ACM.
It is a bounded test, not an OOM or sustained heavy-load qualification.

Source packages: [Alpine v3.23 AArch64 main](https://dl-cdn.alpinelinux.org/alpine/v3.23/main/aarch64/).
Kernel settings: `CONFIG_ARM64_4K_PAGES=y`, `CONFIG_SWAP=y`,
`CONFIG_ZSMALLOC=y`, `CONFIG_ZRAM=y`, `CONFIG_ZRAM_BACKEND_ZSTD=y`.
These are already present in the validated kernel; no kernel rebuild is
needed. `CONFIG_ZRAM_WRITEBACK=y` in that kernel does not enable writeback:
the runtime requires `backing_dev=none` and never assigns a backing device.

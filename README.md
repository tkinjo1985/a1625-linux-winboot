# a1625-linux-winboot

[日本語版 README](README.ja.md)

This workspace contains a safety-first, device-validated native Windows boot
path for the Apple TV HD (A1625 / Apple A8).

The diagnostic entry point remains read-only. The guarded native checkm8/Pongo
build, PongoOS-to-m1n1 uploader, A8 4 KiB-page kernel, minimal initramfs, USB
NCM networking, USB ACM recovery shell, and Dropbear SSH have now been run on
the owned A1625. No boot component mounts or writes internal storage.

## Validated RAM-only chain

The following chain was validated on 2026-09-02:

1. Detect Apple TV normal mode (`05ac:12a7`).
2. Detect DFU mode (`05ac:1227`).
3. Run a Windows-native checkm8 implementation using libusbK.
4. Upload PongoOS and wait for its USB device (`05ac:4141`).
5. Port PongoOS `pongoterm` to Windows/libusb and upload the combined
   `m1n1 + DTB + Image.gz + initramfs.gz` image.
6. Connect to the Linux initramfs using USB NCM/SSH or USB ACM serial.

The validated identity was CPID `0x7000` and BDID `34`; the exact ECID remains
private and is supplied locally as an additional identity gate. The resulting
Linux gadget used `05ac:4142`,
`172.16.42.1/24`, and public-key-only Dropbear on port 22. `/` was `rootfs`,
the complete userspace occupied about 2.6 MiB after boot, telnet was absent,
and no block or APFS filesystem was mounted.

Build the minimal initramfs and combined payload:

```powershell
& .\windows-native\minimal-rootfs\build-minimal-initramfs.ps1
& .\windows-native\build-hoolock-payload.ps1 `
  -BootArgs 'console=ttySAC6,115200n8 loglevel=7' `
  -InitramfsPath .\artifacts\minimal-rootfs\minimal-initramfs.cpio.gz `
  -OutputName m1n1-linux-a1625-minimal-ssh.bin
```

## Safe usage

Run a one-shot diagnostic:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-native\atv-native.ps1 diagnose
```

Monitor USB re-enumeration for 30 seconds:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-native\atv-native.ps1 watch -TimeoutSeconds 30
```

Record the connected service-mode device's port/container baseline:

```powershell
& .\windows-native\atv-native.ps1 baseline
```

Run the self-contained tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-native\tests\AtvNative.Tests.ps1
```

These commands perform no USB control transfers and make no device or system
configuration changes. The `baseline` command writes only the ignored local
file `windows-native/device-baseline.json`, which can contain private USB
identity and topology details and must not be published.

## Codex CLI in RAM

The official Codex `aarch64-unknown-linux-musl` release, code-mode host,
bubblewrap sandbox, CA bundle, and ChatGPT device-code login have been
validated on the A1625. A read-only Codex tool call executed `uname -m` on the
device and returned `aarch64`.

Deploy the pinned runtime and start headless login:

```powershell
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -Login
```

See [windows-native/codex-runtime/README.md](windows-native/codex-runtime/README.md)
for launch commands, credential handling, and RAM limitations. The runtime and
authentication cache disappear on reboot; internal storage is not touched.

To preserve the authenticated state across RAM boots, encrypt it with Windows
DPAPI and restore it after the next deployment:

```powershell
& .\windows-native\codex-state\Save-A1625CodexState.ps1
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -RestoreState
```

The encrypted state defaults to `%LOCALAPPDATA%\AppleTvA1625\state`; plaintext
credentials are never written to the repository. See
[windows-native/codex-state/README.md](windows-native/codex-state/README.md).

## One-command RAM environment restore

After a reboot, put the owned A1625 into DFU and run PowerShell as
Administrator:

```powershell
# One-time private device setup (use the ECID shown by diagnose/DFU output):
& .\windows-native\Set-A1625DeviceConfig.ps1 -ExpectedEcid '<16-hex-digit-ECID>'

# Subsequent RAM-only restores:
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot
```

The script verifies the exact A1625/T7000 artifact hashes, kernel page-size
configuration, and ECID. It then performs only the temporary
DFU/PongoOS/RAM boot chain, restores USB NCM and the Windows NAT, obtains the
new Dropbear public host key over USB ACM, and restores the Codex runtime and
DPAPI-protected login state. It pauses when Zadig must be used for the exact
displayed `05AC:1227` or `05AC:4141` instance; it never changes a driver
itself. Add `-StartCodex` to launch Codex after a successful restore.

To open an interactive PTY-backed SSH shell after recovery, run:

```powershell
& .\windows-native\Enter-A1625Shell.ps1
```

Or perform the complete RAM environment restore and enter that shell in one
command:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot -EnterShell
```

The wrapper selects the newest per-boot host-key file, keeps strict host-key
checking enabled, and uses `ssh -tt`. Inside that shell, typing `codex` starts
the interactive Codex UI. Do not use `ssh -T` for an interactive session;
`-T` deliberately disables terminal allocation.

This command contains no internal-storage, partition, NVRAM, tvOS, or
palera1n fakefs operation. Its Linux payload and Codex installation remain in
RAM and disappear on reboot.

Build and test the native PongoOS uploader without using USB:

```powershell
cargo test --manifest-path .\windows-native\pongo-uploader\Cargo.toml
```

Build the Windows-hardened `openra1n.exe` from pinned source without executing
it:

```powershell
$pongo = '<path-to-reviewed-Pongo.bin>'
$sha256 = (Get-FileHash -LiteralPath $pongo -Algorithm SHA256).Hash
& .\windows-native\build-openra1n.ps1 `
  -PongoPath $pongo `
  -ExpectedPongoSha256 $sha256
```

The source repositories must match their pinned commits, origins, and clean
worktrees. The resulting manifest still marks the binary as unauthorized for
device use until the exact Pongo image and target ECID are reviewed.

Fetch only the public upstream source repositories at the revisions used by
this project (this does not download firmware, Pongo binaries, or Apple data):

```powershell
& .\windows-native\Get-PinnedSources.ps1
```

The `third_party` and `artifacts` directories are intentionally ignored. A
clean clone therefore needs the documented toolchain plus locally reviewed
and built artifacts before the restore command can be used. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance and licenses.

## Safety boundary

Use this project only on hardware you own or are explicitly authorized to
test. It is scoped to Apple TV HD A1625 / AppleTV5,3 / J42d / T7000 and must
not be generalized to another model or SoC without a separate review.

The following operations remain deliberately absent:

- DFU entry automation
- recovery/restore commands
- NVRAM, partition, APFS, or internal-storage operations

No Apple firmware, IPSW content, Pongo binary, compiled kernel, Codex binary,
device identifier, authentication state, or private key is distributed by
this repository. Apple, palera1n, PongoOS, Hoolock Linux, and Codex are names
of their respective owners; this research project is not affiliated with or
endorsed by them.

DFU and Pongo driver changes are restricted to their exact VID/PID and a single
verified connected instance. Persistent storage operations still require a
separate explicit confirmation even though the RAM-only Linux, SSH, NCM, and
ACM milestones have been demonstrated.

## Research basis

- palera1n supports Apple TV HD, but its released CLI is Linux/macOS and the
  official Windows route is a bootable Linux environment.
- Hoolock Linux recommends the PongoOS method and requires 4 KiB kernel pages
  on A7/A8 (`CONFIG_ARM64_4K_PAGES=y`).
- PongoOS uses USB product ID `4141` in its host scripts.
- An unofficial Palera1nWin project demonstrates a Windows-native `openra1n`
  checkm8/Pongo upload followed by a WSL handoff. Its native components were
  treated as research input and separately gated and validated here on the
  owned A1625/T7000.

## License

Original code and documentation in this repository are available under the
[MIT License](LICENSE). Third-party projects and runtime inputs retain their
own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

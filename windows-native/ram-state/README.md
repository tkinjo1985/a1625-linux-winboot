# RAM state snapshots

`Save-A1625RamState.ps1` captures only `/run/work` and selected Codex state files, verifies the connected target is a RAM rootfs with no block devices, validates every archive entry, then stores only DPAPI CurrentUser ciphertext on Windows. The plaintext archive is never written to disk. Its result reports compressed bytes, expanded tar bytes, compression ratio, and download time; these measure state transfer, not the boot payload.

`Restore-A1625RamState.ps1` requires a strict per-boot `known_hosts` file, validates the DPAPI envelope and immutable payload/runtime hashes, then extracts into a staged `/run` directory before applying allowlisted files. Each host snapshot is an immutable encrypted generation selected through an atomic pointer, so an interrupted save cannot pair new ciphertext with old metadata.

The manifest records compressed size and entry count. Use those fields with elapsed time from the caller to compare compression and transfer performance without recording content.

For a no-device preflight, run `Test-A1625RamStateSnapshot.ps1` with the current payload and profile-bundle input. It checks the encrypted snapshot hash and immutable-input compatibility only; it never opens SSH or touches USB. Snapshots fail closed on corruption. `current.previous` is retained for deliberate, manually validated recovery; it is never selected automatically.

## Save and restore

Stop editing the working tree and end Codex commands before saving or restoring.
The lock excludes concurrent snapshot operations, not arbitrary applications.
The default store is `%LOCALAPPDATA%\AppleTvA1625\ram-state` and uses a DACL
restricted to the current user, Administrators, and SYSTEM.

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1

# After the next DFU boot, the wrapper validates the snapshot before USB writes:
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development -EnableZram -RestoreRamState
```

The save wrapper defaults to the `development` profile and the minimal SSH
payload/key under `artifacts`. It prepares the tools bundle on Windows, selects
the most recently modified `state\known_hosts_ram_*` file, then calls the existing
snapshot saver with strict SSH host-key checking. A missing file or host-key
mismatch stops the operation. Use `-KnownHostsPath` to select the verified file
for the current boot explicitly, and `-DevelopmentProfile minimal` if that is
the installed profile. `-PayloadPath`, `-SshKeyPath`, and `-StateDirectory` can
also be overridden. Run with PowerShell 7 after stopping work on the device.

The immutable base remains in Windows `artifacts`: the pinned gzip initramfs,
combined payload, Codex archives, and selected tools bundle. Only mutable state
is encrypted in the snapshot. The authenticated envelope binds the payload,
tools bundle and installer, Codex installer/launcher, schema version, sizes, and per-file
SHA-256 values. Base changes require a new compatible snapshot.

## Saved paths and limits

- `/run/work`, recursively, including `.git` and uncommitted regular files.
- `/run/codex-home/auth.json`, `config.toml`, and `.gitconfig`.
- `/run/codex-home/.ssh/config`, `known_hosts`, `id_ed25519`, and `id_ed25519.pub`.

All other paths are denied: device descriptors, Dropbear server keys,
`authorized_keys`, `/dev`, `/proc`, `/sys`, `/etc`, and internal block devices
are never included. Archive symlinks, hard links, special nodes, duplicate
paths, parent traversal, and privileged modes are rejected. Existing Codex
temporary links are preserved locally during restoration but are not archived.
Limits are 64 MiB per file, 512 MiB total file data, 256 MiB gzip, and 4096
entries. USTAR-compatible path lengths are required; unsupported long-name
metadata is rejected rather than extracted.

Capacity is checked before receiving the archive. The device verifies its hash,
unpacks into a private directory, prepares both work and home, and renames them
with rollback on ordinary failures and catchable termination. SSH and the base
rootfs remain available. After an uncatchable kill, a leftover lock prevents
further restoration; retain it for recovery or boot the immutable base again.
An interrupted host save leaves the previous current generation intact.

Corrupt or incompatible state is never silently accepted. Boot without
`-RestoreRamState` to use the base workflow, or validate a copy of the prior
generation selected by `current.previous` in a separate state directory.
Old encrypted generations are retained; no automatic garbage collection runs.

## Transfer comparison

Gzip over SSH was selected for state: it reduces bytes and keeps credentials
inside the authenticated SSH connection. Raw tar over SSH is the comparison
baseline. Public base assets use hash-checked HTTP over the private USB link;
state is never served by that HTTP server. See
[measured results](../VALIDATION-ISSUES-3-4.md). Snapshot timings cover the
state stage, not DFU/driver interaction or the entire cold boot.

# Codex CLI on the A1625 RAM rootfs

This deploys the official OpenAI Codex CLI, its code-mode host, bubblewrap, and
an Alpine CA bundle to the already-running A1625 Linux environment. Everything
on the Apple TV is written to RAM. It does not mount or write internal storage.

Validated versions and targets:

- Codex CLI `0.152.1`
- `aarch64-unknown-linux-musl`
- Alpine v3.23 `ca-certificates-bundle-20260611-r0`

The script pins and verifies every downloaded archive by SHA-256 before it is
served over the private USB NCM link. It also verifies each archive again on
the Apple TV before extraction.

From a PowerShell 7 session with the RAM-only Linux, USB NCM NAT, and
SSH already working:

```powershell
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -Login
```

`-Login` starts the official headless device-code flow. Open the shown URL on
Windows and enter the one-time code. Credentials are stored only under
`/run/codex-home`, so they disappear on reboot. Never add `auth.json` to this
repository or to an initramfs.

Connect interactively and launch Codex:

```powershell
$knownHosts = 'PATH PRINTED BY Restore-A1625RamEnvironment.ps1'
& .\windows-native\codex-state\Start-A1625Codex.ps1 -KnownHostsPath $knownHosts
```

Save the authenticated state to Windows with DPAPI before rebooting:

```powershell
& .\windows-native\codex-state\Save-A1625CodexState.ps1
```

On the next RAM boot, deploy Codex and restore authentication in one command:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot
```

See [../codex-state/README.md](../codex-state/README.md) for the credential
security boundary. No plaintext credential is stored in this repository.

For a non-interactive read-only smoke test:

```powershell
ssh.exe -T `
  -i .\artifacts\ssh\a1625_ram_ed25519 `
  -o UserKnownHostsFile="$knownHosts" `
  root@172.16.42.1 `
  '/opt/bin/codex-ram exec --sandbox read-only --skip-git-repo-check "Run uname -m" </dev/null'
```

The Dropbear host key is regenerated on every RAM boot. Use the known-hosts
file created for that specific boot; do not disable host-key checking. The
runtime and login both need the Windows NAT route to the Internet.

The A1625 has about 2 GiB RAM. This runtime leaves roughly 1.4 GiB available
in the validated minimal boot, but large repositories, many subagents, or
memory-heavy build tools can still exhaust RAM. The optional
[development tool layer](../development-tools/README.md) adds Git and an SSH
client, with C/C++ tools in its development profile. Its zram option caps
compressed allocation at 256 MiB and never configures a backing device.

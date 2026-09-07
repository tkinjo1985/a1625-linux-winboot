# Persistent Codex authentication on Windows

These scripts preserve the A1625 Codex login across RAM boots without writing
the Apple TV internal storage. The login cache is encrypted with Windows DPAPI
for the current Windows user and stored outside the repository by default:

`%LOCALAPPDATA%\AppleTvA1625\state\codex-auth.dpapi`

Save the currently authenticated RAM session:

```powershell
& .\windows-native\codex-state\Save-A1625CodexState.ps1
```

After the next RAM boot and Codex runtime deployment, restore it:

```powershell
& .\windows-native\codex-state\Restore-A1625CodexState.ps1
```

For normal use, launch the interactive session from Windows with:

```powershell
& .\windows-native\codex-state\Start-A1625Codex.ps1
```

When Codex exits normally, this launcher automatically saves the latest login
cache with DPAPI. If SSH fails or disconnects unexpectedly, it leaves the last
known-good encrypted state unchanged.

The scripts never print the plaintext credential and never write it to the
repository or a temporary Windows file. SSH host-key checking remains strict.
The encrypted file is usable only by the same Windows user on the same Windows
installation. Keep the Windows volume protected with BitLocker and do not copy
the state file as a general-purpose credential backup.

This older helper preserves authentication only. For working files and selected
Git, SSH-client, and Codex settings, use the optional
[RAM state snapshot tools](../ram-state/README.md). They validate archives in
memory and encrypt them with DPAPI; they never extract device archives onto
the Windows filesystem.

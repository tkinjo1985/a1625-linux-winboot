# A1625 RAM-only minimal rootfs

This initramfs contains BusyBox, USB NCM networking, a USB ACM recovery shell,
and Dropbear SSH. It does not include block-device mounting, APFS tooling,
systemd, a package manager, telnet, or a GUI.

Build it from native PowerShell:

```powershell
.\windows-native\minimal-rootfs\build-minimal-initramfs.ps1
```

The default authorized key is
`artifacts\ssh\a1625_ram_ed25519.pub`. The corresponding private key stays on
the Windows host and is never embedded. Output is written under
`artifacts\minimal-rootfs`.

At boot, the Apple TV uses `172.16.42.1/24` and offers the Windows NCM host
`172.16.42.2`. Dropbear listens only on `172.16.42.1:22`, accepts public-key
authentication only, and disables SSH port forwarding. Its host key is created
under `/run` on every RAM boot.

The init script also installs a default route through `172.16.42.2` and public
DNS resolvers. Internet access requires a Windows NAT named `AppleTvRamNat`
for `172.16.42.0/24`; without that host-side NAT, the local USB link and SSH
continue to work but the default route cannot reach the Internet.

# atv-pongo-uploader

A dependency-free Rust prototype for the host-side portion after PongoOS has
already booted. It dynamically loads an explicitly selected 64-bit
`libusb-1.0.dll` and only opens PongoOS USB ID `05ac:4141`.

This tool does **not** implement checkm8, DFU entry, PongoOS upload, driver
installation, restore operations, or internal-storage access.

## Offline validation

```powershell
cargo run --manifest-path .\windows-native\pongo-uploader\Cargo.toml -- `
  validate .\m1n1-linux.bin
```

## Passive PongoOS probe

The DLL path must be absolute to avoid DLL search-order hijacking.

```powershell
cargo run --manifest-path .\windows-native\pongo-uploader\Cargo.toml -- `
  probe --libusb C:\absolute\path\libusb-1.0.dll
```

`probe` opens and immediately closes `05ac:4141`; it sends no transfers.

## RAM upload

The upload command is implemented for review but must not be run until:

1. PongoOS is visibly running on the owned A1625.
2. The combined image was built for AppleTV5,3/T7000.
3. The kernel uses `CONFIG_ARM64_4K_PAGES=y`.
4. The initramfs is gzip-compressed and provides USB Ethernet/serial shell.
5. The user explicitly approves this RAM-only transfer.

```powershell
cargo run --manifest-path .\windows-native\pongo-uploader\Cargo.toml -- `
  upload .\m1n1-linux.bin `
  --libusb C:\absolute\path\libusb-1.0.dll `
  --confirm-ram-boot
```

The protocol mirrors PongoOS `pongoterm`:

- class/interface control request `0x21/1` with a 4-byte payload size;
- bulk OUT endpoint `0x02` with the payload;
- class/interface control request `0x21/3` with `bootm\n`.

The transfer does not include a command that accesses NVRAM, APFS, partitions,
or internal storage. A malformed RAM image can still crash or hang the device.

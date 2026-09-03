# Native Windows feasibility notes — Apple TV HD A1625

Status date: 2026-09-02

## Device identity

The validated unit reported `AppleTV`, USB `05ac:12a7`, status OK, using the
Windows `WINUSB` service. A local `device-baseline.json` may record these
observations and private per-device USB details; it is deliberately ignored.
PID alone is not treated as identity.
Apple TV HD is AppleTV5,3/J42d and uses the T7000 A8
SoC. The Linux device tree independently identifies that combination:

<https://android.googlesource.com/kernel/common/+/1a9239bb4253f9076b5b4b2a1a4e8d7defd77a95/arch/arm64/boot/dts/apple/t7000-j42d.dts>

## Evidence for each stage

### DFU/checkm8 to PongoOS

- palera1n officially lists Apple TV HD as supported, but officially released
  hosts are Linux and macOS:
  <https://github.com/palera1n/palera1n/blob/main/README.md>
- `openra1n` contains a T7000-specific stage 2 and selects it for CPID `0x7000`:
  <https://github.com/palera1n/openra1n/blob/main/checkm8.c>
- Palera1nWin is an unofficial Windows/WSL hybrid. Its vendored native
  `openra1n` fork handles Windows driver rebind and YOLO re-enumeration, and it
  lists Apple TV HD as supported. Public documentation found during this
  investigation only claimed physical validation on A11, so A1625 Windows
  support remains unproven:
  <https://github.com/pwnapplehat/Palera1nWin>

This stage is **device-validated on the owned A1625**. The host-built binary
rejected every DFU serial except CPID `0x7000` plus the explicitly supplied
ECID. It completed checkm8 stages 0 through 3, detected the T7000 YOLO serial,
and booted PongoOS 2.6.3 as USB `05ac:4141`.

### PongoOS to m1n1/Linux

PongoOS's official `pongoterm.c` defines USB `05ac:4141`. Its `/send` path:

1. claims configuration 1/interface 0;
2. sends a 4-byte little-endian size using control request `0x21/1`;
3. uploads bytes to bulk OUT endpoint `0x02`;
4. sends terminal commands using control request `0x21/3`.

Source:
<https://github.com/checkra1n/PongoOS/blob/master/scripts/pongoterm.c>

The Rust `pongo-uploader` implements only these operations and restricts them
to `05ac:4141`. It dynamically loads libusb from a caller-supplied absolute
path. It uploaded and booted the 10,981,708-byte minimal SSH payload on the
owned A1625.

### Linux payload

Hoolock documents and recommends:

`PongoOS -> m1n1.bin -> DTB -> Image.gz -> gzip initramfs`

For A7/A8 it explicitly requires `CONFIG_ARM64_4K_PAGES` instead of the sample
16 KiB configuration:
<https://github.com/HoolockLinux/docs/blob/master/tutorials/SETUP.md>

The documented PongoOS sequence is:
<https://github.com/HoolockLinux/docs/blob/master/tutorials/SETUP_pongoOS.md>

## Proposed native Windows state machine

| State | USB ID | Host action | Current implementation |
|---|---|---|---|
| tvOS service | `05ac:12a7` | Observe only; never replace this driver | Detected |
| DFU | `05ac:1227` | Native T7000 checkm8 | Validated on A1625 |
| YOLO DFU | usually still `05ac:1227` with changed serial | Wait/rebind only this instance | Validated on A1625 |
| PongoOS | `05ac:4141` | Upload Pongo/m1n1 commands | Probe/upload prototype |
| Linux gadget | `05ac:4142` | USB NCM/SSH and USB ACM recovery shell | Validated |

The state machine must match both VID/PID and device instance/serial. A driver
must never be replaced globally for every Apple USB device.

## Required gates before the first USB write

1. Obtain the exact tvOS/device information using a read-only query.
2. Build the Windows `openra1n` fork from pinned, clean source; do not use an
   opaque executable.
3. Require CPID `0x7000`, the owned device's exact ECID, and a reviewed Pongo
   SHA-256 before any exploit stage.
4. Install a driver only for the DFU/Pongo hardware instance after explicit
   approval, with a documented rollback to the Apple driver.
5. First test only `DFU -> checkm8 -> PongoOS`; do not append jailbreak
   overlays, ramdisks, KPF, fakefs, restore, or storage commands.
6. Inspect the combined Hoolock image and record its SHA-256 before upload.

## Explicitly excluded

- `palera1n -f` and rootful/rootless jailbreak installation
- fakefs/bootstrap/package-manager installation
- NVRAM modification
- restore/update/downgrade
- APFS, partition, or internal-storage access

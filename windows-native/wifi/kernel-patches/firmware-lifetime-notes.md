# PCIe firmware setup lifetime

Current result: the completion fence and reset-work guard are deployed and
passed real firmware setup/removal. The combined DART fixes then enabled
WPA2 networking. See [the final acceptance record](../acceptance-2026-09-09.md).
The staged investigations below retain their contemporaneous failure results;
references to unbuilt or untested candidates describe those earlier stages.

The pinned kernel's brcmfmac PCIe probe starts firmware loading asynchronously
via `brcmf_fw_get_firmwares()`. `brcmf_pcie_setup()` later uses the bus and
device state. The original `brcmf_pcie_remove()` frees that state without a
setup-completion fence. A fixed observation delay does not establish that the
callback has finished using it.

`0003-wait-for-pcie-firmware-setup.patch` adds a completion initialized before
the firmware request. Setup signals it after its last state access on success.
On failure it signals after crash reporting but before `device_release_driver()`:
remove may already hold the device lock while waiting. Setup does not access
the freed state after signaling. Remove waits before reading console state or
releasing the bus, rings, IRQ and mappings. Synchronous probe failure paths do
not enter the driver's remove callback and keep their existing cleanup.

This is a lifetime fix, not a timeout or firmware-cancellation mechanism.
If loading is still waiting on firmware fallback, remove waits for that request
to complete. No assumption of success follows from elapsed time. The firmware
loader retains its own device reference until its worker exits; driver unbind
releases devres, including the per-device MSI domain, before the host's parent
MSI domain is removed.

Native Windows build and machine-code review passed on 2026-09-08. The new
ELF has build ID `3f8ec525c8d8598b04f09fc7e96d4469bf10e5b0`. Disassembly
shows `wait_for_completion()` at removal entry, `complete_all()` at successful
setup exit, and `complete_all()` before `device_release_driver()` on failure.
The 4 KiB configuration and linked Wi-Fi/DART symbols passed the existing gate.
Image derivation from ELF and gzip round-trip checks passed.

Separate payload `m1n1-linux-a1625-wifi-fw-lifetime.bin` is 11,377,460 bytes,
SHA256 `a2d151944c1fa813d59d60861354c3b5294d8931ffa91d3b16525716495afdae`.
Use restore profile `wifi-fw-lifetime`; the previous payloads remain available.
The new kernel booted on the owned A1625 on 2026-09-08. Its live GNU build ID
matched the ELF above; USB NCM/ACM, SSH, 4 KiB pages and RAM rootfs passed.
The existing bounded PCI/DART/MSI/BAR probe also passed with module SHA256
`319a7fc2ae21c8f547ce59f0e4dedf213922e4be20b8e84d41a07a0a27949dca`.
It enumerated both expected devices, assigned both endpoint BARs, verified
MSI programming and removed the host with zero rejected config writes.
Radio power/reset, DART, MSI and PCIe power cleanup passed; no PCI devices,
IOMMU groups or probe modules remained. This did not bind brcmfmac, initiate
endpoint DMA or generate an interrupt. Firmware initialization and the new
completion fence under active firmware setup remain untested.

## Remaining host configuration review before binding

The diagnostic host still rejects bus mastering and does not add the endpoint
for driver binding. Passing BAR assignment does not authorize firmware setup.
Review the brcmfmac reset path as well as its initial resource acquisition:
`brcmf_pcie_reset_device()` writes the full link-control/status dword at 0xbc
around a watchdog reset. Upper status bits can have write-one-to-clear semantics;
they must not be treated as ordinary restorable control bits.

The same reset path, for PCIe core revisions at most 13, also accesses config
registers indirectly through BAR-mapped CONFIGADDR/CONFIGDATA. That path bypasses
the host's ECAM config-write guard. Its list includes command/status, PM, MSI,
link control 2, resizable BAR, L1 substates and BAR configuration. Core revision
and these side effects must be accounted for before treating the ECAM allowlist
as complete. Chip revision alone is not the PCIe core revision.

The SBMBX write at 0x98 is a doorbell command and must not be replayed during
snapshot restoration. BAR0 window selection at 0x80 also needs scoped handling.
The completion patch addresses asynchronous state lifetime only; it does not
resolve these configuration, DMA, interrupt or firmware acceptance checks.

Bounded live EROM identification on 2026-09-08 found pointer 0x1810d000, seven Broadcom components and one PCIe2 core (0x83c), revision 11. Probe module SHA256: 488068d5ebcc770d0cc771acf7a69fb0f54b091febfb00d7867f642c2239b160. BAR/window/decode and radio/power rollback passed. Thus the reset path for PCIe core revisions at most 13 applies to this device; its indirect configuration replay and second SBMBX doorbell must be included in the firmware-stage review.

The first actual firmware trial booted BCM4350 RTE 7.35.180.119 and reached the first control query, which timed out while retrieving cur_etheraddr. No usable Wi-Fi interface resulted. Removal waited for the outstanding firmware requests and restored host/radio resources, but warned in cancel_work_sync because bus_reset had not yet been initialized after failed brcmf_bus_started. Patch 0004 adds the same initialized-work guard already used by the reset scheduling path. It passes git apply --check but is not yet applied, built or deployed. The control-response timeout still needs independent diagnosis.

Patches 0004 and 0005 are now built into a separate diagnostic kernel with build ID bb36fc73f999704902582641d1d36a97dfc06c5c. Config/symbol checks, ELF-to-Image derivation, ARM64 4 KiB header and gzip round-trip checks passed. Restore profile wifi-fw-response pins payload SHA256 18f1eb8512de9e1b09227079534eaf1e1dacfb34db7105b79901964defbdbc2c (11,377,511 bytes). This new kernel is awaiting RAM boot and runtime verification. The probe also now counts MSI EOI callbacks; these are handler-delivery observations, not proof of successful firmware responses.

Runtime verification of the diagnostic kernel passed on the owned A1625. The same first control query still times out, but the uninitialized reset-work warning no longer occurs. Failure metadata: mailbox 0, mask 0x30300, shared flags 0x20005, DMA index size 0; ring 0 read/write 0/17, ring 1 0/255, rings 2 and 3 0/0. All eight MSI EOI counters were zero. These observations do not establish the root cause; investigate H2D notification and DMA consumption as well as interrupt delivery. Host/radio cleanup and restoration of the temporary firmware timeout to 60 seconds passed.

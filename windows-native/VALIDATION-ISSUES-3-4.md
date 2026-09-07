# Issue 3 and 4 validation

Measurements on the owned Apple TV HD A1625 / AppleTV5,3 / J42d / T7000,
2026-09-07. The kernel reports `aarch64`, 4 KiB pages, RAM rootfs and tmpfs
`/run`. The device's ECID, keys, and credentials are omitted.

| Check | Evidence |
|---|---|
| Git HTTPS clone/fetch | Git 2.52.0 cloned and fetched this public repository; HEAD `8482c124048b17b166e5c4f9a3521fb5ca8815f4` |
| Codex Git worktree | Codex 0.152.1 ran both `git rev-parse --is-inside-work-tree` and `git rev-parse HEAD` in the clone; returned `true` and the expected commit |
| Development tools | GCC/G++ 15.2.0 compiled and ran C and C++ programs; make 4.4.1, pkg-config 2.5.1, OpenSSH 10.2p1 ran successfully |
| Development asset size | Final bundle 95,907,199 bytes compressed; 274,842,634 bytes declared package files; deployed directory 273,024 KiB |
| Minimal asset size | 10,536,771 bytes compressed; 24,343,171 bytes declared package files; deployed directory 24,016 KiB; Git/SSH/fetch worked after switching from development and compiler links were removed |
| Available RAM after tools | 1,337 MiB during the development verification |
| zram setup | 768 MiB logical disk, priority 100, zstd, 256 MiB compressed memory limit, `backing_dev=none`; repeat activation preserved active swap |
| Bounded memory/recovery test | 128 MiB allocated and paged out; `/proc/swaps` showed 131,072 KiB used while both SSH and ACM answered; all pages read back correctly |
| State save/restore | 81 archive entries, 268,800 raw-tar bytes versus 107,423 gzip bytes (60.0% fewer); SSH download 0.218 seconds; restore 0.36 seconds |
| State integrity after restore | Git HEAD unchanged, clean worktree, Codex login status successful; plaintext auth never written to Windows disk |
| Cold reboot | Physical power cycle and DFU, verified checkm8/YOLO, PongoOS, 10,981,816-byte Linux payload, new ACM-verified SSH key, runtime/tools/zram, and encrypted snapshot restore all succeeded; state restore took 0.22 seconds |
| Cold-boot post-check | Same clean Git worktree and commit, HTTPS fetch and Codex login status succeeded; 1326 MiB available RAM; only zram0 in `/proc/partitions` |

The pageout test is bounded, not an OOM test. The kernel may cache swapped
pages in zswap before writing them to zram; `/proc/swaps` measures logical swap
usage, not compressed zram allocation. An SSH connection temporarily stalled
after the Codex test; ACM showed a healthy system and SSH later recovered.

Host tests include archive/envelope/DPAPI validation, successful restoration,
injected commit failure, insufficient capacity, and corrupt gzip. Git Bash on
this host creates a file copy for `ln -s`; POSIX symlink success is not claimed
from that host test. The real device restoration preserved existing Codex
temporary links and working authentication.

The final development bundle SHA-256 is
`B6F9DF345B35DFA51AFF93B8D95F229F09842DCDC758D7E3C602018D7B53110E`.
After the final installer changes, a fresh compatible snapshot was saved and
restored: 110,171 gzip bytes from 268,800 raw-tar bytes, download 0.213 seconds,
restore 0.242 seconds. Git HEAD and clean status, `codex-ram login status`, and
the wrapper's snapshot preflight passed. Installer transaction tests also
exercise stale package exclusion and root/wrapper/marker rollback.

All actual device operations were RAM-only. No internal disk was present in
`/proc/partitions` before zram activation; subsequent checks permit only zram.
No partition, APFS, NVRAM, tvOS, restore, or jailbreak installation was performed.

Cold boot required rebinding both clean and YOLO DFU instances from WinUSB to
libusbK. Driver interaction time is excluded from state timing. The existing
USB layout check was corrected to wait for all three Linux interfaces to
enumerate; the existing redirected-input driver prompt now stops instead of
looping. Existing USB NCM/NAT settings were reused without elevation.

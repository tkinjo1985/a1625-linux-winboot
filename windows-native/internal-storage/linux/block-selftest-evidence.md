# Synthetic block frontend runtime evidence

Owned J42d/T7000, running Linux 7.2.0 Build ID
4776c5754ce5ac725ac272d841f0a7dee2c4156a.
Test module SHA256:
48b1562927cdab6f518e5a5150efd523efd8ce59c811333862880491f00f5846.
Upload to RAM /tmp matched the host hash. No ANS controller, firmware mapping,
DMA or NAND interface is present in this synthetic module.

- Module load succeeded; ans1ramtest0 reported ro=1, size=128 sectors,
  logical_block_size=4096.
- Direct read of page 1 returned 4096 bytes, SHA256
  586fc0d5f3fe03674e84b19d980e1844860bccb7644dea7733618d46506328e9,
  matching the independent host formula.
- `blockdev --setrw /dev/ans1ramtest0` failed with Read-only file system;
  sysfs ro remained 1.
- Direct read of injected-error page 15 failed with I/O error/status 1.
- Subsequent direct read of previously valid page 1 also failed/status 1,
  confirming the frontend's failure latch through the actual block layer.
- Module removal FAILED: rmmod returned Function not implemented. The matching
  baseline has CONFIG_MODULE_UNLOAD unset. The synthetic device/module remains
  present, read-only and error-latched; SSH remains responsive. No forced unload
  or reboot was attempted. Teardown runtime validation is NOT achieved.

Partition auto-scan is disabled in the initial frontend with GENHD_FL_NO_PART.
Raw GPT sectors remain readable through the whole disk when a real controller
is eventually attached; this test contains no GPT or NAND reference evidence.
No cold boot, concurrent unload stress, persistent write, or real storage read
was performed. Issue #5 remains incomplete.

After that run, source was updated with a write-only `stop` module parameter
which destroys the synthetic disk under a mutex, independently of module unload.
Writing false is rejected; there is no restart. The updated module compiled but
has NOT been loaded: the currently loaded older module lacks this parameter.
Do not assume regenerating local artifacts changes the live instance. The hash
above identifies the old tested instance, not the newly rebuilt artifact.

The updated stop function passed host lifetime/order mocks via
`test_selftest_stop.py`: false/malformed input preserves the live pointers,
true destroys disk before unregistering parent, pointers are cleared, a second
stop returns ENODEV, and subsequent cleanup does not double free. These mocks
do not exercise kernel sysfs or actual disk-drain scheduling. The live old
module remains unchanged; runtime cleanup has still not been validated.

## Subsequent v2 runtime cleanup validation

Built a separate instance with `prepare-block-selftest.py --v2`, module
ans1_ram_selftest_v2, disk ans1ramtest1, parent ans1-block-selftest-v2.
SHA256 85f854978e727744b1eb79d1cc091c3d52b7d8331d85e0ee338e171505469a17
matched after upload. Load reported ro=1 and size=128; direct page-1 read
matched the same expected hash above. Writing true to the v2 stop parameter
succeeded. Both its sysfs block device and parent device disappeared, and dmesg
reported synthetic disk removed. SSH stayed responsive. This validates the
idle-disk stop path on the actual kernel; concurrent stop/read stress is not
covered. Module code remains loaded because CONFIG_MODULE_UNLOAD is disabled.
The old ans1ramtest0 remains read-only and error-latched; v2 does not alter it.
There were no controller/DMA/NAND operations or reboots in either run.

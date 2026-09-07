# A1625 DFU/Pongo driver recovery

The restore script uses libusbK only for the single owned device's DFU
(`05AC:1227`) or Pongo (`05AC:4141`) instance. Match CPID `7000`, BDID `34`,
and the private configured ECID before selecting an instance. Never change
the normal tvOS, USB NCM, or USB ACM driver.

Before changing a driver, open that instance's Properties in Device Manager
and record its driver provider, version, service, and INF name locally. Keep
the record outside the public repository because it may contain the ECID.
Record whether the previous driver was WinUSB or Apple's driver; restore
that actual previous choice if the test is abandoned.

If the temporary boot fails, first stop the host transfer process. In Device
Manager, select the same instance, open Properties > Driver, and use Roll
Back Driver if available. Otherwise use Update driver > Browse my computer >
Let me pick, and select the previously recorded compatible driver. If it is
not listed, stop and obtain that exact original package before proceeding.
Do not uninstall shared driver packages or replace drivers for all Apple
devices. Reconnect the USB cable and confirm the instance is healthy.

A RAM boot does not need a tvOS restore, erase, update, or internal disk
operation. Those operations are outside this recovery procedure.

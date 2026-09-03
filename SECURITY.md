# Safety and responsible use

Use this project only with an Apple TV HD A1625 you own or are authorized to
test. Confirm AppleTV5,3 / J42d, CPID 7000, BDID 34, and the locally supplied
ECID before any device-affecting stage.

The implemented boot path is temporary and RAM-only. It deliberately contains
no internal-storage, partition, APFS, NVRAM, tvOS restore/update/downgrade,
fakefs, jailbreak installation, or `palera1n -f` operation. Do not add such an
operation to the one-command restore path.

Zadig driver changes must be limited to the single displayed DFU (`05ac:1227`)
or PongoOS (`05ac:4141`) instance. Never replace every Apple USB device driver
globally. A failed temporary boot should be recovered by power cycling or tvOS
restore using Apple's supported process; any persistent operation needs a
separate risk review and explicit confirmation.

Do not report a device ECID, USB serial, ContainerId, physical USB topology,
SSH private key, Codex authentication state, Apple-derived data, or generated
artifact in a public issue. Reports may include redacted logs, CPID/BDID,
generic VID/PID transitions, and reproducible host-side failures.

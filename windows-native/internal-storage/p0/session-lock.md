# P0 host session lock

The smoke tool now calls reserved ANS proxy slot 0xf07 with address zero to
allocate and bind one 4 KiB read/export buffer. The C implementation seals the
session **before** this allocation. Allocation failure does not unseal it.
ANS initialization requires this sealed session and a valid bound buffer.
The reserved slot with that buffer address still copies the saved IDENTIFY
response; no additional IDENTIFY is issued.

After sealing, `proxy_process` permits only P_NOP, P_ANS1_INIT, P_ANS1_READ,
P_ANS1_RESERVED and P_ANS1_SHUTDOWN. The existing ANS one-attempt latch prevents
reinitialization. Generic free, allocator/heap changes, arbitrary calls, writes,
SEP operations, exit/vector, reboot and chainload proxy operations are rejected
before dispatch. No host command can unseal the session.

The UART proxy transport independently refuses raw MEMWRITE before its initial
probe writes. MEMREAD is restricted to the bound 4 KiB buffer with overflow-safe
bounds checks, including after an error/shutdown. This prevents raw writes from
modifying the lock and restricts reads to RAM intended for transfer. It also
means firmware/identity acquisition must finish before sealing. IDENTIFY copy
and NAND READ cannot be redirected to another pointer.

Denied proxy/transfer operations, truncated requests and checksum errors abort
the ANS session. A failed non-NOP P0 proxy operation also invokes the idempotent
abort path. Abort latches DEAD and the attempted flag, then requests shutdown;
the existing stop-attempt latch preserves buffers and prevents repeated stop
operations. It never makes a DMA-stop claim.

Evidence: `test_session_lock.py` compiles the actual predicates and session
helpers, exhausts proxy opcode values 0..65535 plus UINT64_MAX, checks RAM
transfer boundaries/overflow, immutable preparation and abort latching. The
production proxy/UART dispatch hooks are built, but the entire transport and
USB-disconnect/exception behavior have not been hardware-tested. This is a
host-entry restriction, not proof that every possible exception/reset path in
m1n1 or hardware is excluded. No P0 firmware has been loaded in this work.

The P0-only startup now skips automatic payload scanning and SEP initialization.
If its action/proxy loop returns, it reenters the proxy instead of progressing
to next-stage teardown/vectoring. `test_startup_object.py` checks actual compiled
main.o references; this is a direct-startup-call check, not a complete call-graph proof.
The general pre-experiment proxy and existing RamOnly defaults are unchanged.
The current P0 tool uses no generic operation after sealing. Do not use a
different tool to bypass the preflight or to start another phase in this boot.

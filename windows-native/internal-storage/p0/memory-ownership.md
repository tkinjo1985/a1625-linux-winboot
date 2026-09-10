# P0 firmware and shared-memory lifetime

Buffer preparation seals generic proxy operations, checks T7000/J42d and the
ANS ADT layout, reads the preloaded firmware region, then reserves the heap
ceiling **before** allocating the P0 read buffer or powering ANS.

`heapblock_p0_reserve_firmware` uses the same physical RAM base and
`mem_size_actual` as m1n1's identity mapping. It rejects an empty, unaligned,
overflowing or out-of-RAM firmware span; firmware below the current heap break;
an invalid boot-data/heap ordering; or overlap with the raw m1n1 image through
linker `_end`. This P0 artifact is the raw build without an appended next-stage
payload. Loaded binary verification must establish that artifact identity.

The heap ceiling becomes the earlier of the previous ceiling and firmware
start. It cannot subsequently be raised or removed. `heapblock` allocations
now reject alignment/addition overflow as well as crossing that ceiling.
The configured dlmalloc has no mmap backend, uses heapblock for MORECORE, and
rejects shrinking sbrk requests, so its previously obtained arenas are included
in the checked current heap break. No firmware bytes or firmware MMIO registers
are modified by this reservation helper.

The selected physical/IOVA/size tuple is retained in AKF state. Immediately
before ANS remap writes, the tuple read from ADT must still match; otherwise
mapping fails. Missing/negative firmware-child offsets are rejected.

| Region | Owner / publication | Lifetime policy |
| --- | --- | --- |
| Preloaded firmware | Boot firmware owns contents; P0 borrows the validated ADT span for AKF mapping | No patch, free, unmap or heap reuse; reservation survives shutdown |
| Read/export buffer | P0 allocates and binds 4096 bytes before ANS power | Sole read SGL and IDENTIFY export destination; retained through the boot |
| Command buffer | ANS allocates aligned storage, then registers exact address and tag 0 | Retained even after sleep/CPU clear or uncertain registration failure |
| RTKit syslog/crashlog/IO-report | RTKit allocates a bounded rounded block on a permitted address-zero request | Replacement/preallocated foreign addresses rejected; free/unmap entry points retain AKF buffers even after reply failure |
| RTKit/AKF descriptors | Host-side owners of the above records | Retained; no repeated controller initialization |

`test_heap_reservation.py` compiles the actual reservation/allocator functions
and exercises overlap, out-of-range, alignment, immutable/previously stricter
ceiling, exact-boundary allocation and overflowing allocation rejection.
`test_session_lock.py` mocks reservation success to isolate host-entry controls;
it does not substitute for this reservation test or a live layout observation.

Limits: boot/ADT metadata and `mem_size_actual` (which upstream can infer when
absent) are not independent hardware attestation. Current-device layout, loaded
payload/firmware hashes, identity and all published live addresses still need
to be captured for the one authorized experiment. Heap separation does not
prove firmware behavior, DMA quiescence or absence of persistent side effects.

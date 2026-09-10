# P0 RTKit outbound allowlist

The actual `rtkit_akf_send` boundary calls `rtkit_p0_allow` before serializing
the message and calling `akf_send`. Boot, endpoint, buffer reply and power code
use the same AKF operations table, including callers that bypass `rtkit_send`.
Policy rejection latches the RTKit error state and prevents transmission.
The separate `ans1_exec_command` gate validates ASP storage command contents.

`type` below means bits 55:52 of the RTKit payload, not the storage opcode.
All other bits must match the expected value or listed fields. A cumulative
128-attempt transport limit also applies. Policy state lives in the single
RTKit instance; ANS initialization is attempted only once per boot.

| Destination | Allowed value | Required state / bound |
| --- | --- | --- |
| management EP 0 | type 6, state 0x220 | Once; configured, aligned 128-byte command buffer address before boot |
| management EP 0 | type 2, min=max negotiated version | Once after received HELLO; chosen version 10..12 lies within received range |
| management EP 0 | type 8, matching map base and protocol-specific done/more bits | One reply per received map base, at most 8 bases; no further maps after done |
| management EP 0 | type 5, endpoint index and bit 1 | Once per advertised endpoint; system 1/2/3/4, or 8 for v11+; application 6 preferred over 5 for v10, 32 for v11+; no alternate application retry |
| management EP 0 | type 0xb, state 0x20 | Once after map completion and observed IOP state 0x20 |
| application EP | exact command address shifted 16, size field 2 | Once after READY and AP-on; address registered locally before RTKit boot |
| application EP | 0x2000001 (tag 0, offset 0, size 128 bytes) | Once after command-buffer READY |
| application EP | 0xff003 (ring tag 0) | After registration; one outstanding command; at most 5 total; successful tag-0 completion clears outstanding state |
| system EP 1/2/4 | type 1, requested page count, owned DVA | One buffer reply per endpoint; pending address-zero request; exact retained allocation address and rounded size; aligned 16 KiB, address fits 42 bits |
| system EP 2 | type 5 plus low-eight-bit index | Exact echo of one pending syslog notification after buffer publication; no other payload bits |
| system EP 4 | type 8 or 0xc, no payload bits | Exact echo of one pending IO-report notification after buffer publication; known upstream acknowledgement envelopes, not exploratory storage operations |
| management EP 0 | type 0xb, state 0x10 | One quiesce request after HELLO; forbids further application TX |
| management EP 0 | type 6, state 1 | Once after quiesce request and observed AP quiesce ACK (v10 permits its known state-zero ACK) |

Unknown received system-message types and unhandled application messages during
boot/power switching now return failure rather than only printing a warning.
The RX transport is cumulatively bounded at 512 messages. This is not yet a
complete verification of all inbound field combinations or live protocol order.

Evidence: `test_rtkit_policy.py` compiles the production policy and exercises
synthetic v10/v11/v12 sequences plus wrong address/tag/state/endpoint, duplicate
messages, concurrent rings, sixth ring, selector-shaped application words,
unowned-size buffer replies, unsolicited/repeated ACKs and premature/repeated sleep.
`test_rtkit_budget.py` checks the actual transport wrapper rejects a denied policy
without invoking the mailbox sender. These are host tests, not real firmware traces.

Independent boundaries: `sep.c` also calls raw `akf_send` for its own controller.
The P0 session lock now rejects generic proxy calls, SEP operations and raw writes
after sealing; see `session-lock.md`. Pre-experiment setup and full exception-path
behavior remain separate audit work. MMIO policy, current device identity and
firmware/heap placement remain in `preflight-audit.md`.

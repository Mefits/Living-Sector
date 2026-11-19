# PERF E handoff — 2026-11-16, authoritative bounded size probe

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262; no merge.

Code SHA: `6e26884c2870595b2ce049248332190ee64df908` (new N39 size probe); `0a04075330e0da99fa75eaabf0e6e4ed1ec4b062` (actual N158 worker integration).
Test SHA: `44e2787c52a06e65ec9e33d4f00e6663d6205a3a`.

Files:
- `godot/scripts/sim/phase2/n158_authoritative_size_probe.gd`
- `godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd`
- `godot/tests/p2_perf_e_authoritative_size_probe.gd`

At exact successful paid ticks 100/300/600/900, the existing owner worker now samples an authoritative detached N39 world snapshot (reuses the economy FrameView snapshot if available) and emits `size_probe` and `size_probe_wall_usec`. The latter is explicitly part of request/projection elapsed time and must not be mistaken for source tick CPU. Counts: ships, facilities, sum of N21 dock queues, N39 receipt categories, contract_board.contracts. Missing fields are flagged; **N9 ledger receipts and source event queue remain unavailable**, not silently inferred from N39. Does not retain World aliases or modify simulation, cadence, balance, N9, N38 or UI.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured speedup; no parity or FPS claim. Sampling can miss a boundary if a single request advances across it; future acceptance harness must request one paid tick per boundary or explicitly report missing sample. The four snapshots introduce diagnostic overhead; `size_probe_wall_usec` records it.

NEXT: connect exact N9 journal and SourceClock event counters through their owners' read-only primitive APIs, and compare 100/300/600/900 same-seed phase windows with a bounded <=12-minute run. Do not label the partial N39 receipt count as total receipts.

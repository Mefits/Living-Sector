# PERF B · Actual N9 paid-path hotpath timing · 16.11.2026 18:34 MSK

- Code commit: `154eab8a88f31db5a5d58e8b2e7ae43122f28702`
- Test commit: `1a084600eadd778e997590a8104d697299bce1ff`
- Files: `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_n9_paid_path_timing_negative_20261116.gd`
- Test status: **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**. No Godot 4.7.2 runtime executed in this shift. No measured speedup.
- What changed: `LS_PROFILE_N9_APPEND=1` enables timing inside the REAL `_append_receipt()` and `_snapshot_receipts()` call paths, with append calls/total/max microseconds, old shard rows copied, full snapshot calls/total/max microseconds, and authoritative receipt count. Disabled by default; no added snapshots or full history traversals. Exposed as read-only `paid_path_profile()`; does not change N9 authoritative receipt storage, snapshot format, financial validation, or N38.
- Negative test: rejected duplicate operation cannot increase committed append counter; parent/fork independence, full snapshot/restore equality, disabled counters zero. The test branches on actual environment flag, so it can run both with and without profiling.
- Evidence: previous Linux late-tick benchmark (Actions #43856475886) proves rising ships/dock/markets/factions and N39 deep copies, but does **not** isolate N9 append cost. This patch enables distinguishing true N9 shard COW growth from hypothetical growth without new provenance helpers. No attribution of the 10x slowdown to N9 is claimed.
- Next: owner E or checkpoint runner should sample `ledger.paid_path_profile()` at paid ticks 100/300/600/900 with `LS_PROFILE_N9_APPEND=1` and log **deltas** per interval (not lifetime totals). B then compares per-append cost vs shard rows and full-snapshot cost, and only if a real material N9 hotspot is established replaces the actual source path with equivalent immutable index design. Do not add uncalled helper methods. Keep exact N9/N38/BT/RNG/paid contract parity.

# PERF B · Receipt COW growth diagnostic · 16.11.2026 17:00 MSK

Branch: `integration/perf-astra-5-workers-20261116`; PR #262, no merge.

- CODE: `009d06c4917e793e009a59570de76a6b7ca07ff2` — `credit_ledger.gd::receipt_storage_profile()`. Read-only bounded (256 shards) measurement: count, occupied/largest shard, mean rows, expected copy-on-write shard-detach rows per append, number of order chunks and flat-cache validity. No full receipt scan or snapshot; no money/receipt/save mutation. Exposes a plausible growth mechanism in `_append_receipt` without asserting it causes the observed 10x.
- TEST: `322e825938719b7360513b65f8d5253600a832fa` — `godot/tests/p2_perf_b_receipt_storage_profile_20261116.gd`, 300 genuine paid transfers, parent/fork isolation, strict N9 restore and index oracle.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. No Godot runtime used, no measured speedup; this is instrumentation, not a performance fix.
- Risk: the existing 256-shard COW structure duplicates a selected shard on each receipt append. Per-append cost can grow with receipt count even when fork is cheap. The new read-only counters permit checking that hypothesis without duplicating journal history. The estimated metric assumes uniform next-ID hash; real IDs may not be uniform.
- NEXT: have E sample this bounded method at paid ticks 100/300/600/900 alongside per-phase and per-site timing, and compare real N9 commit/fork time. Only if commit growth is material consider a staged immutable shard write optimization with strict fork, N38, tamper and replay parity. Do not optimize an unmeasured N9 hypothesis or enable N38 vNext.

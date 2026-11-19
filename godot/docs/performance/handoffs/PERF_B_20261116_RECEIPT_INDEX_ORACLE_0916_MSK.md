# PERF B · N9 receipt index oracle · 2026-11-16 09:16 MSK

- CODE COMMIT: `0091c3467d5740cf05398c87dc199313bf8daa11`
- TEST COMMIT: `f2a7a0babf324e9763f058b51649801b15a1d305`
- FILES: `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_receipt_index_audit_check.gd`
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN (no Godot execution).
- WHY: N9 now has an explicit full-scan, read-only consistency oracle for persistent receipt shards, ordered IDs and O(1) kind counters. It detects duplicate/missing IDs, wrong shards, stale aggregates and extra shard entries. It never exports mutable receipt references and does not change transaction, save, or World behavior. No measured runtime speedup; diagnostic guard only, O(receipt history).
- NEGATIVES: tampered N38 restore must fail without modifying current index; intentionally corrupted kind count, missing and duplicate order IDs must fail; independent fork/restore pass.
- NEXT: run targeted Godot script and use the oracle at bounded ledger/world/N38 checkpoints to compare optimized indexes against authoritative receipts; avoid per-tick invocation.

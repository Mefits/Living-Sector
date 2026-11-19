# PERF B · N9 per-kind receipt index · 2026-11-16 07:00 MSK

- Branch: `integration/perf-astra-5-workers-20261116`, PR #262; no merge or separate PR.
- CODE COMMIT: `a712756168f1a52c51a105ab95973d2193245304`.
- TEST COMMIT: `1964c408452349f7eda6dd38091bb2ed029eddec`.
- FILES: `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_receipt_kind_index_check.gd`.
- WHY: old per-kind provenance summaries required a full receipt snapshot/history scan. N9 now maintains exact kind counts on authoritative append and validated restore; `fork()` detaches the small counters dictionary. Query `receipt_kind_count(kind)` is O(1) and does not return mutable receipt aliases. Historical records missing a kind are omitted from kind counters but still counted in `receipt_count()`.
- INVARIANTS: no change to existing receipt payload, order, N38 envelope, money, transfer, cargo, rollback, restore rejection or active N39 integration. Failed replay does not increment; failed restore does not publish counters. No new authority or sidecar ledger.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source reviewed for preloads and signatures; Godot not executed. No measured performance improvement is claimed.
- TARGETED TEST: initial and repeated trade count, crew wages, wallet write-off, parent/child fork isolation, restore reconstruction, tampered restore rejection, duplicate operation, legacy missing-kind record.
- NEXT: run `godot --headless --path godot --script res://tests/p2_perf_b_receipt_kind_index_check.gd` at a coordinated checkpoint; compare counts with full snapshot in a real N9/N39 checkpoint, and only then consider replacing expensive full-history category scans in B-owned provenance consumers. N38 size measurement remains independent.

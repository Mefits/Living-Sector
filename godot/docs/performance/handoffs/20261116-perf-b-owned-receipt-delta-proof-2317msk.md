# PERF B — N9 owned receipt proof, 16.11.2026 23:17 MSK

CODE COMMIT: ad6fe7ec907c267e35bf5dfd90d3a93f576afd9c
TEST COMMITS: 8839fefb50099d1750b2a77efe851ee8d747d983, 6f414d53c45c1ccc19352e4a218c3af79f62f763
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_owned_receipt_delta_proof_20261116.gd
TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
MEASURED SPEEDUP: none; no Godot execution or same-seed proof yet.

Actual B-owned site: retains_owned_receipts(parent), invoked by transaction ownership proofs. Previously every proof compared 1024 shard headers and scanned detached historical rows. A direct trusted fork now records its parent generation and changed shard IDs, checking only detached shards and their original immutable receipt identities. Any parent append/restore (even same-count), unrelated ledger, or restored ledger falls back to the original exhaustive identity oracle. No new ledger source of truth, no N38 format change, no N39 edit, no receipt data exposed. Generation is not serialized and resets on restore. This targets per-proof fixed 1024 scan, not an established explanation for 137→839 ms late-tick slowdown.

NEGATIVE REGRESSION: child append/parent isolation; parent mutation invalidates shortcut; same-count restore must not bypass identity oracle; tampered restored receipt rejected; exact snapshot and index audit. Godot runtime not available in this tool environment; syntax/parity remain unverified.

NEXT: run targeted test and same-seed site call/time measurement before/after in the single bounded coordinated CI checkpoint. If retains_owned_receipts calls are rare, do not claim meaningful speedup and pivot B to measured N9 append/snapshot and N38 encoded-byte growth at ticks 100/300/600/900. Exact N9/N39/N38/BT/RNG/cargo/contract parity required before adoption.

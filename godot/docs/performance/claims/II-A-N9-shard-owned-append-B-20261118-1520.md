# Astra II-A — N9 receipt shard owned append

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 15:20 Europe/Moscow
BASE SHA: efc2635f3d29c746be54f2e25c58a39eab8ea376
ASTRA: II-A append-only history / owned transaction overlays / provenance.

CODE SHA: cb42e00bba48e9a44f4991ca2b7e7c46db5c312b
TEST SHA: 83c08112ba3e07b27bba33d0f5306d3c6aaad5e7
FILES:
- godot/scripts/sim/economy/credit_ledger.gd
- godot/tests/p2_perf_b_n9_shard_owned_append.gd

CHANGE: The opt-in same-shard reuse path now verifies ownership by exact shard object identity instead of trusting a stale bucket flag. On identity mismatch it detaches before writing, and updates the owned reference. Existing fork and restore revoke ownership; default COW remains unchanged. This protects against index replacement and cross-generation aliasing without changing N38 v1 format.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
REGRESSION: fast-vs-legacy exact balance/receipt oracle, repeated same-shard appends, parent/sibling forks, stale ownership/header replacement, failed duplicate and insufficient-funds transactions, N38 restore, tampered restore, full receipt index audit.
RISK: Experimental LS_N9_PRIVATE_SHARD_REUSE remains opt-in. Godot parser/runtime and long-run parity have not been executed. No Actions started.
NEXT ASTRA II-A: run same-seed late-tick N9 append/shard-copy profile and verify private-shard reuse with exact N9/N38 parity before considering default activation. Otherwise move to measured N38 save-size growth / restart acceptance.

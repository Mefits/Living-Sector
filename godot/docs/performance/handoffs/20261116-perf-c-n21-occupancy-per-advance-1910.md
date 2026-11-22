# C — N21 paid-tick dock occupancy cache (2026-11-16)

CODE SHA: da934ca7513b348312ee68caf8f6d7015a7c8674
TEST SHA: 24f37d408edd3671cb4a4e3ab062523c5d9309e6

Files: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_occupancy_fee_oracle_20261116.gd.

Why: the actual N21 advance queue loop repeatedly called _occupants, which scanned all ships for every capacity check, fee calculation, and admission. With Q queued admissions and S ships this adds O(Q*S) scans on late ticks. This patch builds one local count in O(S), uses it in the real advance path and increments after successful _admit; request/release and all other callers retain the original full-scan fallback. N9 paid transfer, duplicate receipt guard, queue ordering, source fee and N38 state unchanged. Cache is never persisted or shared between calls.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. Added oracle compares _fee with cached and uncached occupancy for 240 distinct ships and changed occupancy; no Godot runtime used. No measured speedup, no same-seed tick100/600/900 parity yet. Existing broader paid-contract/cargo/N38 replay gates still required.

NEXT: run targeted oracle and bounded same-seed early/late ship+dock site measurements, then inspect whether N21 full World duplicate dominates despite reduced O(Q*S) scans. Do not edit A-owned N39 without coordination.

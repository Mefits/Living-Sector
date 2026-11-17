# PERF D — Head owned roster sort, 17.11.2026 01:41 MSK

CODE SHA: 481a34aad96485957f4ce0e162423906b8ae8bba
TEST SHA: 18c4bcb39ec264bad7be57c5f4bb4b1c03ad6ca5

Files:
- godot/scripts/sim/phase2/unified_native_hybrid_planning.gd
- godot/tests/p2_perf_d_head_owned_roster_oracle_20261117.gd

Live Head capture formerly sorted *all* facility and ship IDs before filtering to one faction. Now it filters IDs first and sorts only the owned subset, retaining the same key comparison and iteration order. No new cache, World owner, planner budget, price, contract or RNG changes. Complexity: O(F + ownedF log ownedF + S + ownedS log ownedS) versus O(F log F + S log S). Existing contract filter-before-sort remains untouched.

Negative oracle covers 180 facilities/ships, foreign owners, transfer into alpha, deletion, stable order and snapshot isolation. Godot not executed: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured improvement claimed. Existing CI baseline late window: markets ~39.43s, factions ~39.34s over 300 paid ticks; this change's site contribution is unknown.

Next: run targeted test at bounded coordinated checkpoint; same-seed early/late phase/site calls and p95, capture ownership counts, exact Head decisions and N38/N39/N9 parity. If negligible, focus on measured N150/Head DTO hotpath. Do not touch N152 ContractBoard until A/B ownership agreed.

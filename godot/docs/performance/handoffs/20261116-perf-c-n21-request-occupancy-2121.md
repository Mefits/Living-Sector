# C · N21 request occupancy · 16.11.2026

CODE SHA: `90b5661798dbc5220a754f6a94c9e0b61e406774`
TEST SHA: `3e1fd794e3705df672b6a977cb7383151884bab1`

Files: `godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd`, `godot/tests/p2_perf_c_n21_request_occupancy_oracle_20261116.gd`.

N21 request previously recomputed full-fleet `_occupants` per facility and `_fee`/`_admit`. Request now builds invocation-local occupied counts once after pruning and shares them with head/fast-path fee/admit. No persistence across calls or N38. No change to queue order, eligibility, paid transfer, cargo, BT or tie-break. Asymptotic occupancy scans change from O(candidate_facilities * ships) to O(ships + candidate_facilities) for the request path; no measured runtime benefit yet. `advance` already had an invocation-local occupancy map and was not changed.

TEST: NOT RUN; CODE_UNVERIFIED. Oracle covers 2000 ships, capacities, fee arithmetic equivalence, immutable source, and stale occupancy on the next request. This unit oracle does not establish end-to-end N9/N39/N38 parity. CI not launched. No speedup claim. Next: bounded same-seed 100/600/900 ship+dock phase/site profile, paid contract/cargo parity and N38 restart; inspect whether request is frequent enough to matter versus deep World staging. Baseline tick900 dock_queue ~88ms/tick (with profiler), not attributable solely to this patch.

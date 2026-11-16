# C · N21 no-candidate World staging · 2026-11-16

CODE COMMIT: 8f798451fd0bf0bd386abc77412b3e68475a60af
TEST COMMIT: 0dac11262f295fc1e04aca23915a0de5a00fc9d2

Files:
- godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd
- godot/tests/p2_perf_c_n21_no_candidate_staging_oracle_20261116.gd

N21 request previously deep-copied the growing World (and when ledger is a Dictionary, all domains) before read-only candidate discovery. Now the exact same _candidates function runs on source World, and only a nonempty candidate list causes staging. No change to candidate ordering, queue/paid dock paths, fees, receipts, fuel, cargo or N9 transfer. Empty-candidate result already returned the original World and ledger, so no new mutable alias is introduced.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No runtime Godot available in this iteration. No measured benefit; this targets only the no-candidate request path, not the entire 26.49s N21 baseline. No Actions triggered.

Next: measure count/time of N21 request with empty candidate list vs queued/admitted paths at same seed tick100/600/900, compare phase p95 and paid contract/N38 parity; revert if rare or not beneficial. Run new oracle with the existing N21 paid-dock tests at bounded checkpoint.

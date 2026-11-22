# PERF D handoff — 2026-11-16 03:00 MSK

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
Code commit: `df4fe69d38a151f57d6ba8173fd3b727abc3d2d2`.
Regression commit: `fb7b89753ce750c22627ce84a069f526cd5d12fb`.

## Code
- `godot/scripts/sim/phase2/p2_perf_d_due_index.gd`: index now maintains id→bucket-position for O(1) cancellation via swap-with-last instead of scanning and shifting bucket arrays. All swaps update moved id position; rebuild remains atomic, take_due removes all positions, output still sorted by original due_tick/phase/entity_id/sequence comparator.
- `godot/tests/p2_perf_d_cancel_index_check.gd`: 1200-event original EventQueue oracle, descending first/middle/last cancellations, reinsertion, exact due-order/payload comparison, alias isolation, duplicate removal and failed rebuild rollback.

## Verification
CODE_UNVERIFIED; TEST_ADDED_NOT_RUN (no Godot runtime executed). Manual source/signature review only. No benchmark measured, no FPS claim. The experimental index is NOT wired to authoritative EventQueue; production remains unchanged. No CI or workflow changes.

## Next
Run both p2_perf_d_due_index_check and p2_perf_d_cancel_index_check in Godot 4.7.2; compare cancellation and take_due timings against original EventQueue at equal event counts/cadence; test restore/restart and max tick bounds before any opt-in production switch. No lease held; domain D isolated files only.

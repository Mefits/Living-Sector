# PERF E — 17.11.2026 — bounded paid-phase sampling

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262; no merge.

CODE: `5fd9deb0546244aefb5d16fc4d9d2431212f1628`, `7e19d4e19164297d59ef9004010ade6596c2a94c`.
TEST: `ab0b92c5e1a4fc27b9f3c7cf7e63138109c13faf`.

Files:
- `godot/scripts/sim/phase2/n158_timed_phase_probe.gd`: opt-in derived runtime probe now accumulates per-phase wall elapsed per paid tick in bounded 100-row detached storage. Gap/restart clears rows; failed phases excluded; multiple calls accumulate; complete phase coverage required. No World mutation, no new worker/UI, no N38 writes.
- `godot/tests/p2_perf_e_paid_phase_window_20261117.gd`: 100-tick window, existing phase_window adapter, deep-detachment, rollover, missing phase, gap, failure regressions.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime invoked. No performance improvement claimed; instrumentation only. Timing is elapsed wall, not CPU. The probe is an opt-in derived class and is not yet evidence from a real production run.

NEXT: targeted parser/regression, then a short same-seed opt-in profile with source-clock/N38/BT/RNG checkpoints, windows at 100/300/600/900, <=12 minute budget. Integrate readout only after acceptance; do not change production worker/UI or repeat Astra fixes.

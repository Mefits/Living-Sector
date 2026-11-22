# Astra II-B — N39 recipe-cadence employment ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A (N39 World)
START: 2026-11-18 20:14 Europe/Moscow
BASE_SHA: PR #262 head at selection; claim commit bb02e4b3855aec48e2ed439a93e602abbe09cc53
ASTRA: II-B bounded owned write sets, rollback and alias isolation; N39 L129/L196 paid tick snapshots.
CODE_SHA: 9010619f50a45d4aac987808c327978363f0197d
TEST_SHA: 4e7d9f38cee73cd0b2ea8c2604c5a04946645f96
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_employment_refresh_owned.gd
CHANGE: recipe-due run_tick previously invoked Payroll.refresh_employment(_world) and mutated canonical household rows before later paid recipe guards. Now computes the exact Payroll.occupied read view, shallow-copies World and populations, deep-detaches only changed households, validates full Schema, and atomically publishes the owned employment stage. The unchanged row and non-recipe tick remain untouched. Existing recipe order, wage, tick cadence and N9 guards are unchanged.
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED
REGRESSION: targeted source Payroll.refresh_employment oracle, changed/no-op/missing employment fields, nested alias isolation, rejected later stage, and invalid household count fixture. The fixture tests ownership semantics, not the full production N39 run_tick or same-seed N38 restart.
RISK: validate before publish adds Schema cost on changed employment ticks; benchmark required. Existing recipe phases can still mutate other rows on their own failure paths; separate claim if proven.
NEXT ASTRA II-B: inspect remaining actual L129 snapshot callers in N39-owned phases and remove repeated copies only where no intervening mutation is proven, with full Schema/N9/N38 parity.

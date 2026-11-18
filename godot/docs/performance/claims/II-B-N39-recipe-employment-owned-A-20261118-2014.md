# Astra II-B — N39 recipe-cadence employment ownership
STATUS: IN_PROGRESS
OWNER: A (N39 World)
START: 2026-11-18 20:14 Europe/Moscow
BASE_SHA: pending PR head read
ASTRA: II-B bounded owned write sets, rollback and alias isolation; N39 L129/L196 paid tick snapshots.
SCOPE: recipe-due Payroll.refresh_employment mutates every population row on authoritative _world before subsequent recipe operations. Make employment refresh an atomic owned stage, avoid unchanged-row deep copies, keep exact occupied/cadence/Schema oracle; ensure failed validation cannot leak employment writes.
INTENDED_FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_employment_refresh_owned.gd
EXPECTED_TEST: positive exact refresh oracle, unchanged rows, invalid Schema rollback, nested alias isolation, no-op cadence.

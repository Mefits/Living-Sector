# Astra II-C / D — station administration borrowed read-only planning inputs
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 14:43 MSK
BASE_HEAD_SHA: 4aa9b96fb35d0fa365632e0891496464c7d1bbf4
ASTRA: II-C station/faction/market rosters; remove redundant full copies on real due staffing path.
INTENDED_FILES:
- godot/scripts/sim/phase2/unified_native_station_administration_phase.gd
- godot/scripts/sim/strategy/station_administrator.gd
- godot/tests/p2_perf_d_station_borrowed_inputs_oracle_20261118.gd
EXPECTED: preserve sorted station facility decisions and snapshots; read-only borrowed stock/prices/resources; no mutable alias in returned plan or snapshots; positive and negative tests; no Actions.
RISK: planner must not mutate borrowed World maps; legacy oracle comparison and N38 parity still required.

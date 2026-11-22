# Astra II-C / D — station administration borrowed read-only planning inputs
STATUS: CODE_DONE_TEST_UNVERIFIED
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

CODE_SHA: 6e1d59f19e4813b72f146489210d4d8ada17ca8c (adapter), 70931330d4e2d4a0e3950f5667810dd087d36926 (N18 planner)
TEST_SHA: dfb265e8a178f41607901eaf922260b06fae6590
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
CHANGED:
- N18 due-cycle adapter borrows read-only stock, prices, limits, shortage counters, body resource maps from World instead of five deep copies per station/job.
- StationAdministrator.plan sorts a shallow copied array of read-only facility DTOs, avoiding a deep copy of every nested body_resources map.
- Recipe execution still copies stock into isolated probes; persisted _last_plan, snapshot, retained decisions and returned N18 views remain owned.
ORACLE: 3 due ticks compare old deep-owned input to borrowed input; plan/snapshot parity, returned alias mutation, unextractable mining source, N18 adapter World immutability.
RISKS: Godot parser/runtime and paid N39/N38 exact parity remain unverified. Read-only assumption holds for current StationAdministrator.plan, but future mutations must restore ownership.
NEXT ASTRA: II-C Head/faction repeated global contract and ship scans with a bounded per-planning-cycle read view, avoiding persistent World caches and preserving exact decision order.

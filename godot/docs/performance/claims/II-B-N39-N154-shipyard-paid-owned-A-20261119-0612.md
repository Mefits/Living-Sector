# Astra II-B — N154 shipyard paid owned rows
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-19 06:12 MSK
BASE_SHA: 19b6c1a63911f19e0f6c2febd85ada03dc77cb7c
ASTRA: II-B bounded owned write sets, local validators, versions & delta; N39 L129/L196
INTENDED: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n154_shipyard_payroll_owned.gd
SCOPE: N154 real shipyard module paid stage; detach producer/owner, eligible households, local market; preserve payroll blocked writes, N9/Schema publication, rollback and alias isolation.
TEST: positive deep-copy oracle and negative failed-payroll/invalid-state/alias regression; NOT_RUN until executed.

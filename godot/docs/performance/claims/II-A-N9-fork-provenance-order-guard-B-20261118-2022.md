# Astra II-A / B — N9 fork provenance order integrity
STATUS: IN_PROGRESS
OWNER: PERF B
START: 2026-11-18 20:22 Europe/Moscow
BASE SHA: 66057229e78dbade9a523732408982760901f43d
ASTRA: II-A append-only + stage overlays + invariant transaction + provenance; bounded fork provenance must prove receipt order as well as shard identity.
INTENDED FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_fork_provenance_order_guard.gd
EXPECTED: strict child/parent lineage, unchanged prefix order, no forged or removed receipts, negative tamper cases and positive fork append/restoration; no full-history scan on trusted paid path.
TEST: NOT_RUN

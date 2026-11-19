# Astra II-A — B bounded provenance single-lookup
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-19 12:20 MSK
BASE_SHA: 689cb363f8b4f2ef877ed1b5d85c1d1cc780767b
BACKLOG: II-A N9 append-only + stage overlays + invariant transaction + provenance
SCOPE: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_bounded_provenance_lookup.gd
GOAL: Remove redundant shard hash probes in bounded receipt/provenance paid read paths, preserve detached copies and exact proof failure semantics; positive and negative oracle regression.
TEST: NOT_RUN

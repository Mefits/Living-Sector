# Astra II-A — N9 incremental flattened receipt cache

STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-18 19:16 MSK
BASE SHA: 5032a1e1e7b51a993924f00b3c3549133eec9188
ASTRA: II-A N9 append-only history, owned stage overlays and bounded provenance; avoid repeated full-history scans on paid path.
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_flat_cache_delta.gd
PLAN: preserve immutable base flattened cache through paid appends and fork, track bounded new receipt IDs, rebuild only delta at snapshot boundary; restore clears lineage. Exact snapshot/order/fork and negative alias/replay oracle.
TEST: targeted positive and negative Godot regression; TEST_NOT_RUN until runtime available.

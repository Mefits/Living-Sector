# II-C N84 dock receipt lookup
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 15:27 Europe/Moscow
BASE SHA: b3a70728e3f032ad820af24338953c96f2f9f420
ASTRA: II-C fleet/contracts/dock hotpaths; reduce repeated dock receipt materialization, preserve exact DockDwell semantics.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_receipt_lookup.gd
TEST: independent latest-dock receipt oracle, multiple ships, malformed/non-dock receipts, fresh proposal invalidation, BT DockDwell boundary.
RISKS: receipt iteration order and live authoritative N21 proof; never cache across paid ticks.

## Result
CODE SHA: 96a5364f8ea1c76f43e81f96323a38541639dfff
TEST SHA: 6bf44abc86d6eb3891277ec721f377961971caf0
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
CALLSITE: _dispatch DockDwell -> _latest_dock_ticks; no cross-tick persistent cache.
EFFECT: keep only physically docked ship IDs in latest N21 receipt projection, avoiding growing historical removed/undocked ship entries; preserve original max receipt tick and append-only ordering for every active DockDwell consumer. N39 World not modified.
NEGATIVES: historical removed/undocked IDs, undock action, older receipt, per-proposal cached view, fresh proposal invalidation after new receipt and changed dock ownership, no World mutation.
RISK: still scans all historical receipts once per proposal; benefit depends on count of removed/undocked ship IDs and N21 receipt history; no paid-tick benchmark yet.
NEXT ASTRA II-C: dock/contract paid-tick occupancy and N84/N153 24/100/500 full BT/cargo/fuel/route/N38 oracle, with actual phase profile.

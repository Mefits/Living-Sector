# II-C — N84 active-row read-only gates
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 01:30 MSK
BASE SHA: 8210dcd94b6470ee3a1b819a9d478a17bed5b0e4
ASTRA: II-C ship/BT owned boundary.
CODE SHA: dbdba30573162de3b6a7b9784781651abd4d924a
TEST SHA: 307a529ade4ac4abfba1d3045316721d3ca8f488
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_readonly_gates.gd
CHANGE: Read-only active N84 BT validation and N104 obligation proof now precede costly deep ownership of nested ship row. N91 materialized-site branch explicitly acquires ownership before writing; normal N104 resume and BT tick acquire ownership after validation. No authoritative World write or new cache. Preserved original rejection priority for autonomous plans and contracts.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
COVERAGE: invalid autonomous BT, missing N104 contract, wrong fulfiller, sleeping no-op and nested cargo/memory alias negative.
RISK: Runtime oracle and N38/BT paid-tick parity remain unverified. Savings apply only to early rejected active rows, so this is a bounded optimization, not a claimed fix for late-tick degradation.
NEXT ASTRA II-C: dock occupancy and N153 contract candidate scans with versioned invalidation and paid 24/100/500 fleet parity.

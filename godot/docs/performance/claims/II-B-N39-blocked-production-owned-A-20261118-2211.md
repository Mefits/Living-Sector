# Astra II-B · N39 blocked production owned writes
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
DATE: 2026-11-18 22:11 MSK
BASE SHA: c80ea5e27b5360a4be07b6a3b6ae61982d104af0
TASK: replace direct authoritative facility writes in `_blocked` shared by recipes/mining with isolated validated row stage; preserve blocked reasons and source economic behavior.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_blocked_owned.gd
EXPECTED TEST: actual N39 _blocked entry, positive/negative, deep-copy oracle, nested alias, no mutation on invalid stage.

CODE SHA: 6e69645f0e6e5992792b6957ee19f1d3eb02e063
TEST SHA: 5406e842d3336380507c87223451c7b0d1e42ef2
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED
RESULT: Shared blocked recipe/mining path now detaches changed facility row and performs full Schema validation before publication. Positive deep-copy oracle, negative shallow-alias, nested alias, malformed/missing row and no-op regression added, not run. This is a narrow correctness improvement, not measured speedup.
NEXT: Astra II-B remaining deep:L129 caller-level snapshots; coordinate C-owned ship/dock callsites and prove no intervening mutation before reusing a snapshot.

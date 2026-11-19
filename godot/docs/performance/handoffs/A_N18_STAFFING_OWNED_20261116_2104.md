# A handoff — N18 staffing copy narrowing, 2026-11-16

CODE COMMIT: 28ee03d814533b2e6a9decdf99fb5645a698b7e0
TEST COMMIT: 12df0e89267d9e6a0b66192ac704f72a78692b75

Files: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n18_staffing_owned_copy_20261116.gd.

N18 due staffing previously cloned the entire growing N39 World at _copy_world("L277", true). It now shallow-copies the root and deep-copies only facilities, before changing assigned_workers. The new station_administration value is independently duplicated as before. Other domains are not written by this stage. Existing Schema.validate and Schema.accounts comparisons are retained. This is one fewer full World deep-copy per due N18 staffing call, not a measured speedup. Subsequent _world stages and caller ownership require full same-seed parity validation.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No Godot runtime test or CI executed. Negative test demonstrates why root-only shallow copying is unsafe; positive test checks detached facilities and unchanged source. This standalone test is an ownership boundary regression, not an N38/N9 economic oracle.

NEXT: run targeted Godot test and same-seed N39/N9/N38/BT/RNG parity. Measure N18 due-call frequency, deep:L277 baseline vs shallow root+facilities cost at early and late windows. Coordinate with C for repeated ship/dock world_snapshot() callers; do not modify C-owned code. Revert if parity or timing fails.

# PERF A — N91 empty dispatch hotpath (16 Nov 2026)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `9b9bf891ecb277dd84a437802b8556d5b7793ca9`
TEST COMMIT: `3e212e43e9729f96a1932e040b31b17f3e71ee5d`

FILES:
- `godot/scripts/sim/phase1/n39_native_world_production.gd`
- `godot/tests/p2_perf_a_n91_empty_assignments_hotpath_20261116.gd`

WHY: `apply_native_construction_assignments` previously deep-copied the entire growing authoritative World at measured copy site `L2008`, then ran full Schema.validate and Schema.accounts even for an empty source N91 proposal array. This is a true no-write/no-receipt path. The early return retains the existing successful status/tick/empty assignment payload and leaves nonempty proposals on the original guarded path. The branch only executes after readiness, canonical tick, and construction_sites checks. It neither exposes a mutable alias nor changes N9, N38, BT, RNG, source cadence, cargo or construction.

TEST: `p2_perf_a_n91_empty_assignments_hotpath_20261116.gd` compares full byte-serialized N39/N9 snapshot before/after empty dispatch, full Schema.validate oracle, and verifies a nonempty invalid proposal is still rejected without mutation. TEST EXECUTED: NOT RUN; CODE_UNVERIFIED (no Godot runtime exercised). No performance improvement claimed. This removes one deep World copy and its validation/account scans per *eligible empty* N91 invocation; frequency and late-window CPU savings remain unmeasured.

NEXT: E/C should report actual N91 empty-proposal call counts at tick 100/600/900 and N39 copy-site timings; run targeted test at one bounded CI checkpoint and compare same-seed early/late CPU ms per paid tick, exact N9/N39/N38 parity. For ship/dock World snapshots at deep:L129, C should identify consecutive read-only callsites and request a precise N39 owned projection; A must not edit C-owned callers.

# III/E — paired paid-tick drift oracle
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 04:47 MSK
BASE_SHA: c318e99ab306f8a532ab9438d12b31b10ef6d5d4
ASTRA: III / long-run evidence — same-seed bounded early/late paid-tick and direct-vs-threaded comparators; exact N38 parity.
CLAIM_SHA: 8a918f13f25dd084c37d13462e4564cff6eac1ed
CODE_SHA: 98b294e33593ba10dba509b8c338335e6ee8aac2, fe824e77b33f3f7efd5181bb0a4609f32f347aa2
TEST_SHA: b221e4c0ca0d489567989bf2f570395c82823895
FILES: godot/scripts/sim/phase2/n158_paired_paid_tick_drift.gd; godot/tests/p2_perf_e_paired_paid_tick_drift.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
RESULT: Bounded 100 real paid-tick aligned direct/worker samples, exact checkpoint gated; per-tick signed worker-minus-direct delta median/p95, count of slower/equal ticks, first-vs-second half drift, unattributed request overhead, early/late comparisons at 100/300/600/900. All scalar, no World retention. Real harness invokes comparator on the existing paid-tick path.
TEST: NOT_RUN; CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED. Targeted regression includes positive alignment and negatives for clock forgery, incomplete attribution, negative durations, parity forgery, sign/total forgery, overlap, false CPU label, mutable sample alias.
RISKS: elapsed wall measurements include scheduling; not CPU, no claim of speedup. Exact N38 restore still checked by existing live harness.
NEXT ASTRA: E same-seed bounded multi-fixture 24/100/500 ships once C fixture is ready; instrument internal copy/Schema/N9 only through A/B-owned interfaces, and measure Windows 100/300/600/900 after user permits.

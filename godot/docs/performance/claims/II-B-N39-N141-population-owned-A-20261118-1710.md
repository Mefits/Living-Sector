# Astra II-B — N39 N141 construction labor population owned writes
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-18 17:10 MSK
BASE HEAD: d557a42061b8d698c99934388ac44aa09c7135ab
ASTRA: II-B bounded owned write sets, rollback and full Schema oracle; N39 paid construction labor.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n141_population_owned.gd
EXPECTED: avoid full population deep copy for non-colony N141 labor, preserve colony B3 fallback, rollback, alias isolation, full Schema/N9 checks. Positive/negative regression against deep-copy oracle.

CODE SHA: e0ebc067484ab4a4acd780d3275d5e1ece51e052
TEST SHA: fb619c6ab5c4fdf74149bd2d601d35729b8bbe8b
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n141_population_owned.gd
RESULT: N141 non-colony shifts now shallow-copy population registry and deep-detach each paid household once before mutation. B3 colony-capable shifts retain original full deep-copy semantics. Source unchanged on rejected stages; strict production Schema/N9 checks remain.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Regression compares full deep-copy oracle, multiple paid sites, later rejected household, nested aliases, B3 fallback; synthetic ownership test, not a real N141 integration execution.
RISK: verify NativeConstructionLabor.paid_shift never mutates its input World and compare real same-seed N141/B3 paid+rejected outcomes before acceptance.
NEXT ASTRA II-B: N39 L129 snapshot caller reuse only with proof of no intervening writes; full Schema/N9/N38 parity.

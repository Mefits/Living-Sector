# III-E detached N38 checkpoint byte growth / parity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 02:47 MSK
BASE SHA: 97832d0e0e7ce00902f35527db02dd06b807015d
ASTRA: E bounded benchmarking protocol; N38 restart/save bytes, N9/World growth and measured observation overhead, same-seed direct/thread acceptance.
INTENDED FILES: godot/scripts/sim/phase2/n158_checkpoint_byte_probe.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_checkpoint_byte_probe_oracle.gd
GOAL: measure actual detached checkpoint serialization byte sizes and encode wall costs at exact milestones without charging paid ticks, compare direct/thread encoded lengths and digest, enforce bounds and positive/negative oracle, retain only scalar metrics.
TEST: NOT_RUN

CODE SHA: 87b1ac8426797bcc45563ec4b429844d0fb61b85, c76fb241b25e9790316ed902c7a365e332c22f94
TEST SHA: c59b36726e1abc2ee6d950ace585b6c3946abfc7
TEST: NOT_RUN; CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
IMPLEMENTED: detached checkpoint var_to_bytes byte size and encode wall time at exact direct/thread milestone; hard 256 MiB per-side bound, scalar-only summaries, early/late growth, strict complete checkpoint coverage; benchmark fail-closed on invalid observations. No canonical N38 mutation, no World retention and no paid-tick charge.
ORACLE: equal checkpoint, scalar detachment, missing parity, wrong tick, unsupported milestone, negative cost, oversized bytes, absent worker, misattribution, duplicate/missing boundary.
LIMITATION: checkpoint serialization is diagnostic size, not native N38 save archive bytes; byte equality is not asserted because equivalent dictionaries may serialize with differing key insertion order. Godot runtime and Windows performance are untested.
NEXT ASTRA E: instrument true internal copy/Schema/N9 callsites with agreed A/B observation hooks; then same-seed 100/300/600/900 measurements and exact N38 restart acceptance.

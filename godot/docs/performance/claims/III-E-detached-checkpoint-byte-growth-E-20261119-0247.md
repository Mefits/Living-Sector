# III-E detached N38 checkpoint byte growth / parity
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 02:47 MSK
BASE SHA: 97832d0e0e7ce00902f35527db02dd06b807015d
ASTRA: E bounded benchmarking protocol; N38 restart/save bytes, N9/World growth and measured observation overhead, same-seed direct/thread acceptance.
INTENDED FILES: godot/scripts/sim/phase2/n158_checkpoint_byte_probe.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_checkpoint_byte_probe_oracle.gd
GOAL: measure actual detached checkpoint serialization byte sizes and encode wall costs at exact milestones without charging paid ticks, compare direct/thread encoded lengths and digest, enforce bounds and positive/negative oracle, retain only scalar metrics.
TEST: NOT_RUN

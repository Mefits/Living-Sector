# Astra III/E — 600/900 bounded direct/threaded source parity
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 18:46 Europe/Moscow
BASE HEAD: a098a7224cd84b8c756b1bb1999830877f57674a
ASTRA: complete bounded early/late paid-tick profiling with exact direct-vs-worker checkpoints, N9/events/N39 growth and N38 restart at 600/900; no worker/UI changes.
INTENDED FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_900_direct_threaded_oracle.gd
EXPECTED: opt-in 600/900 real source ticks, strict 480s wall cap, 100-tick windows at 100/300/600/900, checkpoint and size parity, negative fixtures, no Actions.

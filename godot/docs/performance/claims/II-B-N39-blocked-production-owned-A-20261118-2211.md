# Astra II-B · N39 blocked production owned writes
STATUS: IN_PROGRESS
OWNER: A
DATE: 2026-11-18 22:11 MSK
BASE SHA: c80ea5e27b5360a4be07b6a3b6ae61982d104af0
TASK: replace direct authoritative facility writes in `_blocked` shared by recipes/mining with isolated validated row stage; preserve blocked reasons and source economic behavior.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_blocked_owned.gd
EXPECTED TEST: actual N39 _blocked entry, positive/negative, deep-copy oracle, nested alias, no mutation on invalid stage.

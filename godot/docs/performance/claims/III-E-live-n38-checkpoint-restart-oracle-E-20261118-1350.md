# Astra E — executable N38 checkpoint/restart oracle
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 13:50 Europe/Moscow
BASE HEAD: 7b395981fd825147c459f23332d26c6bec941b4d
ASTRA: E benchmark acceptance / N38 restart parity, 100/300/600/900 bounded paid ticks.
INTENDED FILES: godot/tests/p2_late_growth_capture.gd; godot/tests/p2_perf_e_late_growth_restart_oracle.gd; godot/scripts/sim/phase2/n158_late_restart_oracle.gd.
GOAL: validate persisted milestone checkpoint by fresh N158 restore and exact checkpoint oracle, rejecting mismatch, missing/corrupt files and clock drift; no additional paid ticks or changes to World.
TEST PLAN: positive exact restore, negative changed RNG/clock/cargo and malformed checkpoint; no Actions.

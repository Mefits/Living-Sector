# Astra E — executable N38 checkpoint/restart oracle
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 13:50 Europe/Moscow
BASE HEAD: 7b395981fd825147c459f23332d26c6bec941b4d
ASTRA: E benchmark acceptance / N38 restart parity, 100/300/600/900 bounded paid ticks.
INTENDED FILES: godot/tests/p2_late_growth_capture.gd; godot/tests/p2_perf_e_late_growth_restart_oracle.gd; godot/scripts/sim/phase2/n158_late_restart_oracle.gd.
GOAL: validate persisted milestone checkpoint by fresh N158 restore and exact checkpoint oracle, rejecting mismatch, missing/corrupt files and clock drift; no additional paid ticks or changes to World.
TEST PLAN: positive exact restore, negative changed RNG/clock/cargo and malformed checkpoint; no Actions.

CODE SHA: e635a736df91df6c71bbd9cf49e63afb65353bb3, 32ca6cbe495ea20dd850080ffcf7fa740f2ee666
TEST SHA: 7f1e07cbb80420294cb152b7612d24763317a21b
FILES: n158_late_restart_oracle.gd, p2_late_growth_capture.gd, p2_perf_e_late_growth_restart_oracle_20261118.gd
RESULT: bounded capture now optionally validates saved milestone bytes against authoritative completed checkpoint, restores into a fresh N158 runtime and requires exact restored checkpoint and SourceClock tick. No extra paid tick, no worker/UI changes. Opt-in LS_LATE_VERIFY_RESTART=1 to avoid changing default benchmark timing.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Positive/negative fixtures authored, no Godot runtime executed.
RISK: strict checkpoint equality may expose legitimately transient post-restore fields; requires real N38 test before enabling by default.
NEXT ASTRA E: direct-vs-threaded same-seed source checkpoint comparator with matched paid-tick windows and worker request vs source timing attribution; short 100/300/600/900 acceptance, no Actions until user authorizes.

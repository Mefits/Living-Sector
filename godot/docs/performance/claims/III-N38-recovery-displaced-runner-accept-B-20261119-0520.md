# Astra III — N38 recovery-displaced restart integrity
STATUS: IN_PROGRESS
OWNER: B
TIME: 2026-11-19 05:20 MSK
BASE HEAD: a3027cdd18b2d7f0cce14a8e676d80180c7594a4
SOURCE: ASTRA_FIVE_SHIFTS_RU.md B N38 save/restart growth and recovery
FILES: godot/scripts/sim/save_state.gd; godot/tests/test_n38_recovery_displaced_runner_accept.gd
GOAL: prevent save_runner envelope-only cleanup of displaced checkpoint; require successful live runner restore before deleting displaced, preserve last recoverable save on interrupted recovery; positive/negative/oracle regression.
TEST: NOT_RUN

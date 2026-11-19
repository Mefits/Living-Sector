# Astra III — N38 pending-only survivor guard
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-19 07:21 Europe/Moscow
BASE SHA: 0c6216a260350e815122049e44328114d0c4d7d1
ASTRA: III N38 save/restart, atomic pending/bak, old receipt references, exact replay.
CODE SHA: 3d52397bdc06ff4332b29039b5a2641b9b806ab9
TEST SHA: 47687b1aedcc1c2854379718178aaa968db5d10e
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_pending_survivor.gd
CHANGED PATH: save_runner() now refuses to truncate an existing structurally trusted .pending if no other trusted primary, .bak, .bak.previous, .recovery-displaced or .recovery-rejected exists. New _pending_is_only_recoverable_checkpoint() performs read-only authenticated native-coherence preflight only when pending exists; no format, currency or cadence changes.
TEST: NOT_RUN (no Godot execution). Positive: independently trusted primary/backup permits rewrite; no pending and invalid pending permit normal path. Negative: corrupt primary/backup with valid pending is refused, real save_runner returns ERR_BUSY, pending and primary byte oracles remain identical. Existing load_runner pending recovery remains available.
LIMITATION: structural trust is not proof of real Runner restoration; test still requires Godot and actual save/restart. No performance improvement claimed; preflight overhead only on pre-existing pending.
NEXT ASTRA III: N38 actual Runner restart360, interrupted pending recovery with authentic seed and exact checkpoint parity, then save-size growth at paid ticks 100/300/600/900; assess segmented archive only after measured 16MiB pressure.
CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED.

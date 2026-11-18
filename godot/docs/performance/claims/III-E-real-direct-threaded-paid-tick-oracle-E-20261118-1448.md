# Astra III/E — real direct/threaded paid-tick parity
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 14:48 Europe/Moscow
BASE_SHA: 8688a48d9a67498292fa04e7d23f433cf5d2ad81
ASTRA: E bounded benchmarking protocol, direct-vs-worker same-seed exact checkpoint/N38 parity, paid source tick vs worker request elapsed.
INTENDED_FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd (only if necessary).
EXPECTED_TEST: positive exact 100 paid ticks, checkpoint equality; negative wrong tick and divergent checkpoint; bounded timeout, no CI.
RISK: Godot unavailable; no production backend change, no FPS claims.

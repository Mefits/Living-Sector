# Astra III/E — late direct/threaded paid-window oracle
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 15:54 Europe/Moscow
BASE HEAD: 491b20eab4503751059c7974df128edd6701ea88
ASTRA: bounded early/late N158 paid tick comparison, same-seed exact N38/BT/RNG and separated request/projection elapsed; no new worker/UI.
INTENDED FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_late_direct_threaded_window_oracle.gd
EXPECTED: opt-in 300-tick live source direct/threaded parity with checkpoint and 100-tick windows at 100/200/300, failure-safe bounded run, positive/negative oracle. No CI run.

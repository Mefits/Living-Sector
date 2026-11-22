# Astra III/E — late direct/threaded paid-window oracle
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 15:54 Europe/Moscow
BASE HEAD: 491b20eab4503751059c7974df128edd6701ea88
ASTRA: bounded early/late N158 paid tick comparison, same-seed exact N38/BT/RNG and separated request/projection elapsed; no new worker/UI.
INTENDED FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_late_direct_threaded_window_oracle.gd
EXPECTED: opt-in 300-tick live source direct/threaded parity with checkpoint and 100-tick windows at 100/200/300, failure-safe bounded run, positive/negative oracle. No CI run.

CODE SHA: fe225b5c2ddab8f59bf501c7929ed488b13de36c; a600347e6536fb738cfbc004fd3fb34a10c031cb
TEST SHA: 8935e718e55ee187b2ae0242859c7a66535b065e; 4531f88fcf277494b4d3a7e1b9268a55fd20c287
FILES: n158_direct_threaded_acceptance.gd, p2_perf_e_real_direct_threaded_oracle.gd, p2_perf_e_late_direct_threaded_window_oracle.gd
IMPLEMENTATION: opt-in LS_E_LATE_DIRECT_THREAD=1 expands the actual same-seed direct/Thread N158 oracle to 300 paid ticks, exact checkpoints at 1/20/60/100/200/300, N38 restore at final boundary, separately validated contiguous 100-tick elapsed windows at 100 and 300, independent growth attribution (direct advance vs worker advance/projection/request). Default remains 100. All samples detached and bounded to 100.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. No Godot or CI executed. 300-tick runtime has a 180s wall budget; timeout is failure, not parity PASS.
NEGATIVES: reversed/overlapping/incomplete windows, invalid request attribution, negative projection, false CPU label, unverified parity.
NEXT ASTRA E: measure authoritative counts receipts/contracts/dock/events at 100/300 on direct and worker and enforce exact size parity with N38 checkpoints; follow with 600/900 bounded windows once budget permits.

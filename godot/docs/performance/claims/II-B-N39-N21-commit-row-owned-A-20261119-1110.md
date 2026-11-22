# Astra II-B — N39 N21 commit row-owned publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF A
START: 2026-11-19 11:10 MSK
BASE SHA: f71424cbf9bd1f1b56e587da995faabdc4845b92
ASTRA: II-B bounded owned write sets / real N39 World L129/L196; eliminate deep copy of all ships, facilities, dock receipt history in _commit_native_n21_unprofiled after full Schema/N9 oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n21_commit_row_owned.gd; this claim.
TEST: positive/negative detached write-set, retained immutable rows, nested alias, no mutation on rejected proposal, exact legacy deep-copy value oracle. No Actions.

## Result
CODE SHA: 8c909aad043a8ead2ddef74458bd23cebffa41c8
TEST SHA: 819ae768525d744c86d77da60ad74a473a9e28e1
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
FILES: n39_native_world_production.gd (_commit_native_n21_unprofiled, _n21_owned_commit_rows), p2_perf_a_n21_commit_row_owned.gd
EFFECT: after full Schema, N9, FIFO and receipt oracle, deep-detach only changed ship/facility rows and newly appended dock receipts. Keep old immutable history by reference. Rejection returns before atomic World/Ledger publication. Test includes exact old deep-copy value oracle, consecutive writes, nested alias and negative corruption cases.
RISK: unchanged rows are intentionally shared as read-only; any future mutator must detach before write. Godot execution and paid-tick performance unverified.
NEXT ASTRA II-B: inspect remaining N39 N97/N83 paid ship service/free-trade publication and repeated L129 world_snapshot callsites with owner-specific contracts; do not modify C-owned stage files.

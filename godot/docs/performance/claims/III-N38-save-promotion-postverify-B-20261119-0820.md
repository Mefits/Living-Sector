# Astra III — N38 save promotion post-rename verification
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-19 08:20 MSK
BASE SHA: f18ba863cbe389723d89f3e3f3fbfdb083d8d71a
ASTRA: III N38 authenticated atomic pending/bak save/restart
CODE SHA: 52f39b8c3db78fc4a84574117c62f19798a5d587
TEST SHA: bc56d64e4a3d3d4f7052f111002dd45b89178933
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED

FILES:
- godot/scripts/sim/save_state.gd
- godot/tests/p2_perf_b_n38_postpromotion_check.gd

RESULT:
- Production save_runner now opts into authenticated validation of the installed primary AFTER pending rename, before old backup cleanup.
- On failed validation, the newly installed bytes are moved back to .pending; the old primary and parked .bak.previous are restored to their original positions.
- Invalid-primary promotion also restores the previously rejected original if installed verification fails.
- Legacy filesystem-only helper tests retain default opaque fixture behavior; production always requests verification.
- Positive fixture: authenticated primary, old backup rotation, real save_runner. Negative fixtures: corrupt installed candidate with valid primary+older backup and corrupt original primary. Byte-for-byte rollback oracle.

RISK: Godot parser/runtime and full Runner restart parity not executed; file rename rollback can itself fail, in which case surviving named recovery files are preserved and the error returned. No claimed speedup.

NEXT ASTRA III: real Runner save/restart and interrupted recovery durability with exact N38 checkpoint parity; then II-A actual paid receipt growth and snapshot costs.

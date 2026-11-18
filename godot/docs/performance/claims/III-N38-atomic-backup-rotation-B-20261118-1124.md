# Astra III / B — N38 atomic backup rotation under failure
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
STARTED: 2026-11-18 11:24 MSK
BASE_SHA: 24703402c8dbd35b4284ae7f64f80551b25ee747
CLAIM_SHA: cf2e8e10771941ece671a3531740de98c4fe10e0
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — B N38 save/restart, atomic pending/bak, backward-compatible persistence.
CODE_SHA: b130db1e931acbd02c88b74316ffad23b239b83e
TEST_SHA: a716824dc3faf7a7bcb794dc68409f5cffba1bd6
FILES:
- godot/scripts/sim/save_state.gd
- godot/tests/p2_perf_b_n38_backup_rotation_20261118.gd
REAL_CALLSITES:
- save_runner -> _promote_verified_pending (verified .pending promotion)
- load_runner fallback order primary -> .bak -> .bak.previous -> .pending
RESULT:
- Before replacing a valid primary, park the previous backup at .bak.previous, then rotate primary to .bak and promote the verified pending file. No longer delete the only existing backup before a potentially failing primary rotation.
- On promotion error, attempt to restore both original primary and backup; leave the verified pending file for recovery. Refuse to overwrite an orphaned .bak.previous.
- After interrupted rotation, load_runner can restore .bak.previous through the authoritative Runner, with optional promotion to primary.
- No save format, N9, N39, f64, World, contract, balance, or cadence changes. No Actions triggered.
TEST: NOT_RUN (Godot/Windows unavailable in connector execution)
TARGETED_REGRESSION: Positive rotation with existing backup; collision/orphan negative; missing pending rollback negative; invalid-primary promotion preserving backup.
PERFORMANCE: NOT_MEASURED (persistence safety, not paid-tick speedup).
RISK: File rename/remove rollback can itself fail under OS-level I/O errors; full N38 real Runner save/restart and Windows filesystem fault tests still required before acceptance.
NEXT: Astra II-A B — bounded receipt journal growth / private-shard COW cost and exact N38 restart parity at early/late paid ticks; only enable experimental shard reuse after full oracle.

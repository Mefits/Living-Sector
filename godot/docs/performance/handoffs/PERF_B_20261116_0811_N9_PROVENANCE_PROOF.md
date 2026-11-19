# PERF B — bounded immutable N9 provenance proof (16.11.2026 08:11 MSK)

- **CODE COMMIT:** `e04edf3daa7a08afb21664c1901008c80bb0fa85`
- **TEST COMMIT:** `4fbbf0e8b8884f9dedf8dbebb924ed0270db089b`
- **Files:** `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_receipt_proof_without_copy_check.gd`.
- **TEST EXECUTED:** NOT RUN (Godot runtime not available in this session); **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**.
- **Change:** `verify_operation_provenance(expected_rows)` checks a bounded set of operation IDs against private immutable N9 receipts. It compares id, kind, tick and all legs; rejects missing, duplicate, malformed or forged proof rows; returns only bool, never exposes receipt aliases or copies full history.
- **Expected benefit:** avoids a whole-journal snapshot for known-ID N39 proof checks. Not wired into N39 (owned by A); no measured TPS/FPS benefit. Existing authoritative receipt creation, rollback, balances, N38 format and accounting rules unchanged.
- **Negative regression:** invalid/missing fields, wrong kind/tick/legs, absent/duplicate ID, malformed ID, fork and restored proof parity, no ledger mutation.
- **NEXT:** Coordinate with A to replace only appropriate snapshot-based known-operation proof call sites, then run this test, full N9/N39 checkpoint and N38 restart/tamper parity at same seed; measure saved snapshot bytes/time. Do not enable risky backend without those gates.

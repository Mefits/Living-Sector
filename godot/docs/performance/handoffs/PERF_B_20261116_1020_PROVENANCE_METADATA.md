# PERF B — N9 optional provenance metadata (16.11.2026, 10:20 MSK)

- Code commit: `f563713452824b35e0432547249fce264081a9dc`
- Test commit: `fa83896f0ea7de2cf004d2becd327be2788841b7`
- Files: `godot/scripts/sim/economy/credit_ledger.gd`; `godot/tests/p2_perf_b_provenance_optional_metadata_negative_20261116.gd`
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN (no Godot runtime execution). Source-level signature and preload path checked.
- Change: `verify_operation_provenance` previously verified only id/kind/tick/legs, silently accepting forged extra metadata. It now checks every supplied expected field against the stored immutable receipt, rejecting absent or unequal values. Existing required fields and bounded indexed lookup remain unchanged. This closes a provenance false-positive for `account_closed`, `credits_lost`, crew accrual metadata, and future optional fields.
- Benefit: correctness/security of bounded provenance proofs; no measured speedup. No format, balance, money movement, N39, or N38 change. No default backend change.
- Next: execute targeted negative test on Godot 4.7.2 at coordinated checkpoint; verify ledger/N38 restart and compare source receipts. Coordinate N39 adoption with A only after parity.

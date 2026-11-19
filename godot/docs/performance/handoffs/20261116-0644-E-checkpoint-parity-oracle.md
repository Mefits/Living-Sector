# PERF E — exact checkpoint parity oracle (2026-11-16 06:44 CET)

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.
Code commit: `71fbd9c8cb17944029ae1855844b6911485e1ee0`.
Test commit: `0c0cd6ce039c3b869a3f0dc981943d13ad6923f3`.

Files:
- `godot/scripts/sim/phase2/n158_checkpoint_parity_oracle.gd`
- `godot/tests/p2_perf_e_checkpoint_parity_oracle.gd`

Added exact recursive comparator for independently captured completed-tick checkpoints, with deterministic mismatch path, strict Variant type comparison, array ordering, no omitted World/N9/BT/RNG fields, rejection of live Object references, and depth guard. Negative test covers cargo, receipts, RNG, BT, clock type, missing fields, live objects. No runtime wiring, no second World/Runner, no economic changes.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED (Godot 4.7.2 unavailable). FPS / performance benefit: NOT MEASURED. Static inspection only; test output string is not evidence of PASS.

Next: integrate this oracle into controlled direct-N158 vs owner-binding parity harness with two independently seeded runners and full N38 restart; do not enable threaded backend in main until full parity and GUI evidence. No leases taken; only new E-owned files touched. Actions not triggered.

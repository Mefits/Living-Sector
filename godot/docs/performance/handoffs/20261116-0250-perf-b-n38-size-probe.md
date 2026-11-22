# PERF B — exact N38 encoded-byte size probe (2026-11-16)

CODE COMMIT: `ab38c456ef93a78e631c2bd48c62fc30c7ff38d7`
TEST COMMIT: `3f0626c8ef4cb4b6a96b5d6669a61064f2caa59a`

FILES:
- `godot/scripts/sim/phase2/p2_perf_b_n38_encoded_size_probe.gd` — isolated opt-in, read-only diagnostic for actual UTF-8 envelope bytes, including N38 exact-f64 transport, SHA, tab indentation and newline. Uses `SaveState._wrap` and `SaveState.MAX_SAVE_BYTES`, not a duplicated approximation. Reports remaining/over-limit bytes and N9 receipt count when present.
- `godot/tests/p2_perf_b_n38_encoded_size_probe_check.gd` — regression: exact byte count against real SaveState encoder, Unicode, N9 receipt count, legacy P1, input immutability, over-limit rejection.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN; no Godot 4.7.2 execution in this session. No measured runtime speedup, no 420/900-tick or N38 restart PASS claim.

WHY: SaveState already hard-rejects >16 MiB after exact encoding. Before designing a risky N38 segmented archive, we need reproducible real encoded-byte growth with receipt count. This probe can measure representative real checkpoint snapshots without changing save/load, backup rotation, N9 balances, receipts, World, f64 fidelity or the limit. The probe is not wired into the live path; it does not add per-tick overhead.

NEXT: run `godot --headless --path godot --script res://tests/p2_perf_b_n38_encoded_size_probe_check.gd`; if it passes, capture 24/100/500-ship same-seed checkpoints at 420/900 ticks and report `encoded_bytes`, `receipt_count`, slope bytes/receipt, limit headroom. Only then decide whether N38 vNext segmentation is necessary. Preserve atomic .pending/.bak, exact ledger and old format. Do not enable vNext without full restart/tamper parity.

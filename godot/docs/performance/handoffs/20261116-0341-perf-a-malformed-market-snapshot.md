# PERF A — malformed N39 market snapshot fail-closed (2026-11-16 03:41 MSK)

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.

CODE COMMIT: `ecc39ae34dd66c483a12a7489c6ab3a995573e45`
TEST COMMIT: `ec6cc29c13900237d43d2def0451291937674b4d`

Files:
- `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`
- `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`

Change: capture_protected_fields previously returned an empty snapshot when it encountered a non-Dictionary market row. Empty markets could then pass snapshot validation, and a malformed row preceding valid rows discarded all evidence. It now preserves each invalid location with a null sentinel and validate_protected_snapshot explicitly rejects non-Dictionary snapshot/live rows. Regression covers malformed, subsequently healed, and mixed good/bad rows. No changes to production TickRunner, World, N9, N38, balance, or schema oracle. The guard remains opt-in/shadow only.

TEST EXECUTED: NOT RUN (Godot unavailable); CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Static review: existing preload and function signatures retained; only Dictionary/Variant type checks and a null sentinel introduced. Measured speedup: none claimed. This is a safety hardening, not a performance win.

NEXT: coordinate N150 shadow boundary with D; compare guard to full Schema oracle on live paid world, then measure overhead and N38 restart before enabling any optimized path. No CI run.

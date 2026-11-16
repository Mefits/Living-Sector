# PERF A — protected alias reparenting (2026-11-16 08:05 MSK)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE SHA: `e48a6a35ed957c187248cbe0cf27d3b969ae52d0`.
TEST SHA: `702ebdd653b846948a151d3e4abdd2a955f9845b`.

Files:
- `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`
- `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`

Changed the opt-in N39/N150 owned-write guard to reject mutable protected storage shared with a different new field, or nested under a different dictionary key/array position. Previously the alias scan only traversed matching keys/indices and could miss a reparented protected stock reference exposed through an observation field. Added negative tests for protected-to-observation and nested-key reparenting, plus detached illegal write control.

TEST EXECUTED: NOT RUN (Godot unavailable); CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source-level check: existing preloads and signatures unchanged. No CI. No runtime, TPS or FPS improvement claimed. Guard remains isolated; authoritative World, N9, N158, N38 and full Schema.validate unchanged.

Risk: cross-field recursive alias scanning is more expensive than the earlier same-key scan; do not enable on production tick path without targeted Godot regression and A/B cost measurements. Next: run the targeted test, compare against full Schema oracle, benchmark on actual N150 market rows, then coordinate shadow-only integration with D. No files leased.

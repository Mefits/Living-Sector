# PERF E — checkpoint acceptance fail-closed (2026-11-16, shift 11)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

Code SHA: `05b1242b88bc2993f29b092bb44b3ed3304bde76`.
Regression SHA: `26ae060661a944d10daf4fd1f3f1dd8b73cedea7`.

Files:
- `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`
- `godot/tests/p2_perf_e_same_seed_checkpoint_comparator.gd`

Change: comparator now rejects empty/non-string parity fingerprint, incorrect time-kind labels, invalid checkpoint window boundaries and non-integer paid-tick coverage. Previous test updated to supply wall-time label and negative regression added. No N39/N9/N38, economy, worker scheduling, UI or balance changes.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured acceleration or FPS claim. Existing caller still must provide an actual authoritative N38/BT/RNG fingerprint; a nonempty arbitrary string cannot prove parity. This is an acceptance safety improvement, not the requested real-counter integration.

NEXT CODE: inspect the actual N158 paid-tick commit boundary and add opt-in scalar authoritative receipts/contracts/dock/events/ships counters at ticks 100/300/600/900 without World duplication. Validate same-seed source fingerprint and 8–12 minute bounded profiling, not 2600-tick run.

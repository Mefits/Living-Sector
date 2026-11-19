# PERF E — strict checkpoint timing comparison (16 Nov 2026)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE SHA: `b1d65e43ff52500414ea089c9b6a9deabbb2e19b`.
TEST SHA: `1d11173554c19facf5a18db1bf9b6f7c7d35debc`.

Files:
- `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`: `compare_checkpoint_pair` validates exact paid window, complete coverage, detached counts, supplied source fingerprint, elapsed attribution and reports delta/ratio. Never accesses World/N9/N38 or modifies simulation.
- `godot/tests/p2_perf_e_same_seed_checkpoint_comparator.gd`: positive faster sample, negative changed RNG/checkpoint, receipts, incomplete window, missing field, invalid timing and coverage.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution or performance measurements. Comparator cannot itself prove that the supplied fingerprint is a complete authoritative N38/BT/RNG digest; the producer must supply an independently verified exact checkpoint. Counts equality is an additional acceptance gate, not a replacement for source parity. Wall elapsed != CPU time. No measured speedup is claimed.

NEXT: wire scalar authoritative checkpoint fingerprints and exact receipts/contracts/dock/events/ships counts to the existing paid-tick 100/300/600/900 instrumentation (owner-side after commit only); compare same seed before/after C/A/D changes, record source phase timing and N38 restart. Do not rerun 2600 ticks or 35-min CI.

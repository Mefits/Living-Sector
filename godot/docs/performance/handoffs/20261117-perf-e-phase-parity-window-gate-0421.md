# PERF E handoff — 17.11.2026 phase-window parity gate

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262. No merge.

## Code
- `9783da4775f59a8e090572739c0882d55129c918`: `godot/scripts/sim/phase2/n158_worker_request_metrics.gd` adds detached per-phase baseline/candidate comparison only after an external identical nonempty authoritative checkpoint fingerprint. Checks 100 paid ticks, fixed checkpoint boundary, timing kind, finite consistent averages, nonnegative totals/p95/max, and matching windows. Rejects noninteger tick labels in `phase_window`.
- `e6eae8182eb2b871cc25a50637929592aef93527`: `godot/tests/p2_perf_e_phase_parity_comparator.gd` exercises valid phase delta, empty/divergent checkpoint, incomplete coverage, negative total, inconsistent mean, and float tick.

## Validation
TEST_RUN: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime execution or new speed measurements. Prior GitHub Actions #43972442164 PASS predates these commits; cannot be used to validate them.

This does not generate source checkpoint fingerprints; caller must supply real same-seed N38/BT/RNG parity proof. A fabricated matching string cannot certify parity. Existing `phase_window` still needs wiring to actual per-paid-tick phase timings. No World/N9/N38/worker/UI/balance/AI code changed.

## Next E code
Wire real authoritative phase timing rows after each committed paid SourceClock tick into a bounded 100-entry ring, then attach exact N38/BT/RNG checkpoint digest to 100/300/600/900 windows. Run bounded targeted test and late-window A/B within 8–12 min; report measured phase avg/p95 and source parity. Do not duplicate Astra 99ab25e9/1676db61 or existing bounded N39/N158 profiler samples.

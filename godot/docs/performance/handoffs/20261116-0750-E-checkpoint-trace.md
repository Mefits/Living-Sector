# PERF E — exact checkpoint trace / restart boundary (2026-11-16)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
Code commit: `8431783c022ad342301c0baa925f4e45eb613295`.
Test commit: `472ccd2c4b6dea93a8c96e8e3041c0ca79a30cf6`.

## Code
- `godot/scripts/sim/phase2/n158_parity_checkpoint_trace.gd`: opt-in, bounded (1024) detached direct-vs-candidate full checkpoint comparison at consecutive committed ticks. Fail closed on gaps, invalid types, live Object aliases, tick mismatch, first exact difference. Explicit N38 restart-boundary equality against last committed checkpoint. Does not create a runner/world/ledger or modify production execution.
- `godot/tests/p2_perf_e_parity_checkpoint_trace.gd`: positive consecutive pairs + restart and negative receipt, RNG, gap, unsafe Object, wrong tick, restart mismatch/boundary tests.

## Verification
- CODE_UNVERIFIED / TEST_ADDED_NOT_RUN: no executable Godot used. GitHub write commits confirmed. No CI run, no FPS measurements, no claim of parity or speedup.
- Source check: both preloads refer to existing scripts; only detached Dictionary/Array and scalar checkpoint data are accepted. No change to main.gd or N158 runtime.
- The trace does NOT generate the canonical snapshots itself: a future harness must capture complete, independent N38/World/N9/BT/RNG checkpoints from two seeded N158 runs. No parity verdict until then.

## Next
Wire a controlled headless harness to capture the *actual* N158 completed checkpoints for direct vs owner-step and N38 restart, run parser/negative checks and bounded parity before enabling any threaded UI backend. Preserve single-owner runtime and opt-in behavior. No lease needed for unique E-only files.

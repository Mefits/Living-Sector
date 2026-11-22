# PERF B · N38 exact encoded growth diagnostic · 16.11.2026 13:36 MSK

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262. No merge or default backend change.

## Commits
- Code: `f6cb62433f83f2666e000116575a71c70bca28b9` — `godot/scripts/sim/phase2/p2_perf_b_n38_growth_probe.gd`.
- Targeted negative regression: `8005eeab45d8f8bedfe853fac57e463cc0331b1a` — `godot/tests/p2_perf_b_n38_growth_probe_check.gd`.

## Scope
Read-only diagnostic measures exact N38 v1 encoded UTF-8 bytes before/after checkpoint, including SHA envelope, exact f64 tags, indentation and trailing newline, using the existing SaveState encoder via the existing B size probe. Checks historical receipt IDs and their full records remain identical before interpreting the difference. Reports byte delta, added receipt count, actual 16 MiB budget, and observed bytes/added receipt (which includes all other checkpoint changes; NOT isolated receipt cost). Rejects missing/changed/shrunk history. Negative test includes tamper, replaced receipt, missing ledger, empty snapshot, no-op, unicode, and legitimate negative byte delta when another domain shrinks. Does not alter save/load, N9, N39, atomic .pending/.bak, world or ledger ownership.

## Verification
CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No Godot runtime invoked; no PASS claimed. Exact encoder and probe preload paths verified against current branch. No measured TPS/FPS or real-world save-size result: fixtures only, test not executed. Code does not raise MAX_SAVE_BYTES or enable segmented N38 vNext.

## Next
At the next shared bounded CI checkpoint, execute `res://tests/p2_perf_b_n38_growth_probe_check.gd` and `p2_perf_b_n38_encoded_size_probe_check.gd`. Feed two real same-seed committed N158 checkpoints at different receipt counts to measure actual encoded growth; if nearing 16 MiB, design opt-in segmented N38 with authenticated manifest and atomic rollback, gated by exact restart/negative tests.

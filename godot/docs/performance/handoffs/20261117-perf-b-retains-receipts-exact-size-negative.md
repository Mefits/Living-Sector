# PERF B · N9 exact provenance map boundary · 17.11.2026

- Code: `c047d982029083816c97396bf0c4b8120566a54e` — `godot/scripts/sim/economy/credit_ledger.gd`.
- Negative test: `9d89cb4f59994c3580bf2c609fd47d207b89fc12` — `godot/tests/p2_perf_b_retains_receipts_exact_size_negative_20261117.gd`.
- `retains_receipts(candidate)` previously compared every existing ID but accepted arbitrary **extra** IDs. It now rejects candidates whose size differs from the authoritative receipt count before scanning order chunks. Equal-sized forged rows still require the existing full content comparison.
- This removes an O(R) scan for malformed size-mismatched candidates and closes a provenance validation gap. It does **not** improve the normal matching-candidate O(R) path and is **not** evidence of late-tick acceleration. No N39 or other-owner files changed.
- CODE_UNVERIFIED; TEST_ADDED_NOT_RUN (Godot runtime not executed). The earlier green CI #43972442164 predates this patch. No CI launched. N9 WeakRef, N152 idle, N158 projections untouched.
- Next: determine real invocation count and time of `retains_receipts` and `_snapshot_receipts` at tick100/300/600/900 using existing paid-path counters, and N38 encoded bytes at actual save points. If ordinary matching scans are not material, stop optimizing N9. Preserve exact same-seed N9/N39/N38/BT/RNG/contract/cargo parity before accepting any risky change.

# PERF A · detached N39 market protected snapshot · 2026-11-16 02:38 MSK

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.

Code SHA: `a358211d817861e7f4152c2dde9f602c99b16baf`. Test SHA: `a96cf188ce38b36cfabe5acc3860121b0e1847ba`.

Files: `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`, `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`.

Added opt-in `capture_protected_fields` and `validate_protected_snapshot`: detached copies only of non-N150-owned market fields; detects in-place mutation of inventory, credits, protected structure even if live World aliases are reused. Negative tests for nested stock, credits, added/removed protected fields, observation-only change and deep snapshot independence. No live N158/N39 commit wiring; strict Schema oracle and N150 observation proposal validator still required. No balance or authoritative World changes.

TEST EXECUTED: NOT RUN (Godot unavailable). CODE_UNVERIFIED. Benefit unmeasured; bounded protected snapshot may cost CPU/memory, requires A/B before production use. Source inspected for Observation.OBSERVATION_FIELDS and validator signatures. No Actions started.

NEXT: coordinate shadow invocation at N150 commit boundary with owner D; compare against full Schema oracle with 420/900 N38, restart and negative mutation tests. Reject experiment if snapshot cost exceeds benefit. No other owner files edited.

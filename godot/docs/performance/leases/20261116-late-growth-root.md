# Late-tick growth investigation

owner: root / direct user request 2026-11-16
status: ACTIVE
base: 1c8b4b2bf7411505876927d730d390ebb3ca10e8
scope: credit_ledger.gd profiling; n39_native_world_production.gd measured growing call sites; n158_production_runtime.gd only if profiling identifies a growing read path; new p2_late_growth_* tests and own handoff.

Do not edit these central files concurrently. No main.gd, UI, interpolation, balance, AI cadence or N38 format changes. Inspect the existing 2600-tick Actions probe first. Short replay windows from genuine early/late checkpoints, exact state and negative tests before publishing changes. Remains in PR262, no merge to base.

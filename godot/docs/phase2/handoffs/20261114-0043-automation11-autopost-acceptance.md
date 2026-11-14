# P2 autonomy — native N135 auto-post acceptance (2026-11-14 00:43 UTC)

- Shared PR: #249; code commit: `c6731cce570ce41beedee7d10027d7509ce90dd9`.
- Added `godot/tests/p2_unattended_autopost_flight_check.gd` based on existing physical-flight acceptance, but **removed manual `post_funded_contract` admission**. The test only establishes a controlled native market demand fixture; N158 markets phase must detect N135 demand and publish a funded N104 delivery contract without a manual call. It then observes the real N153/N14/N21/N15/N97 delivery, money conservation, mid-flight disk save/load and anti-replay checks.
- Real live status: N158 source contains `StationDemand.propose` followed by `production.post_funded_contract` in markets phase. This change adds a stricter acceptance gate; it does NOT itself prove a paid flight or alter runtime behavior.
- Checks: source read and transformed; no manual posting invocation in new test. Godot 4.7.2 executable unavailable in this runtime, so **CODE_UNVERIFIED**, test NOT executed. No GitHub Actions launched, no Windows export.
- Risk: native fixture might not produce an automatically fundable source/destination after N150 repricing; a test failure must be diagnosed from N135 proposals and N104 admission reasons, not treated as autonomy proof. Escrow/contract selection is constrained to native food source/destination.
- Next: run locally `godot --headless --path godot --script res://tests/p2_unattended_autopost_flight_check.gd`; fix the first real failing stage in canonical N39 Apply, then verify in F5. Do not change manual ship UI or introduce second ledger/runner.
- Scope: new test only; all other files free. Lease RELEASED.

# P2 autonomy provenance acceptance — automation11, 2026-11-14 05:59 MSK

- Branch: `integration/godot-phase2-unified-20261113`; shared Draft PR #249.
- Code commit: `1202245a70cb6086931a5eef86dc2b1582a13011`.
- Changed only `godot/tests/p2_autonomous_multitick_delivery_restart_check.gd`.
- Strengthened real hands-off flight gate: a paid delivery must originate in a *new* N135-funded N104 posting observed from `contract_admissions_snapshot()`, with a durable N9 escrow receipt; independent N153 acceptance must be observed through `last_n153_result()`, and its ship must equal the canonical N104 fulfiller. Existing or injected contracts cannot accidentally satisfy the acceptance.
- Preserved the previous physical N14/N21/N15/N97 receipt checks, mid-flight and post-pickup disk restart, N9 money conservation and idempotent payout assertions. No changes to the simulation's authoritative World, Ledger, TickRunner, Board, GUI or workflow.
- Static validation: fetched the resulting GitHub blob `b5416308b96561b2356849cb0f5e303d355fb875`, verified all new read-only method calls exist in N158 and the provenance gates appear in the committed test. Godot executable not installed here; **CODE_UNVERIFIED**, no end-to-end PASS claimed.
- GitHub Actions: **0 new runs**. No Windows export.
- Remaining risk: original 6000-tick test may still fail from actual supply, affordability, N153 candidate selection, route, dock or cargo failures; it has not been run. The controlled N151 consumption history is a test fixture, not a natural zero-intervention production observation.
- Next useful work: run `godot --headless --path godot --script res://tests/p2_autonomous_multitick_delivery_restart_check.gd` with Godot 4.7.2, fix the first genuine engine failure in a large coherent patch; then test clean seed with natural demand and F5 observer.
- Lease `20261114-0455-automation11-autonomy-provenance.json` released. No files reserved.

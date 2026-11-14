# P2 13.11.2026 22:04 MSK — N135/N104 funded escrow candidate
- Branch: `integration/godot-phase2-unified-20261113`, shared PR #249.
- Code: `e0b6b7c713dad9c423367bbcacc737a818209f9e`; test: `5f02b10ee1eff10cdc18c8233ae92b06f68b7d53`.
- Added `unified_contract_escrow_staging.gd`: revalidates N135 against real N39 World and N9 ledger, restores existing N104 board, creates a ZERO-only escrow account on a staged ledger, posts delivery to the existing board, and verifies conservation plus funded escrow.
- Returns BOTH candidate snapshots as `STAGED_NOT_APPLIED`; does not modify canonical world, ledger, board, fleet, or tick. This is deliberate: canonical N158 Apply must publish them together, fail closed on stale tick/world and rollback together. Do not claim live contracts or autonomous delivery.
- Regression `p2_contract_escrow_staging_check.gd`: synthetic physical market deficit, staged funding, no input mutation, duplicate refusal, no funds refusal.
- Verification: CODE_UNVERIFIED. No local Godot binary. No GitHub Actions runs. Test has not executed.
- Lease `20261113-2153-automation11-contract-escrow-staging.json` RELEASED; files free.
- NEXT: coordinate a lease for N158 + N39 canonical Apply, bind one persisted ContractBoard to authoritative ledger; stage and atomically commit board+ledger+facility credit mirrors, preserve save/load. Beware N39 World ledger snapshot may be the only money authority. After live posting, integrate N153 independent ship decision and physical cargo receipts. Do not wire parallel board or second ledger.

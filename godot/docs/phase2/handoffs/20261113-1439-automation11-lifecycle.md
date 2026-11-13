# P2 N156 lifecycle live integration — 2026-11-13 14:39 MSK

- Branch: `integration/godot-phase2-unified-20261113`; shared PR #249; starting HEAD `d17d7095`.
- Commits: `fc937caf` stage; `9cda3d67` canonical apply; `3f8137db` clock scale; `c6fc2a34` schema; `df0a4a01` JSON integer restore; `99153ee6` observer.
- Gate: 1 / N156 facility lifecycle, first live vertical; no new World, ledger or runner.
- Every authoritative N39 paid-world tick now calls frozen N156 proposal before production, with actual Clock.tick_scale() and multiplier.
- Stage commits condition degradation, abandonment counter and abandoned state to the SAME facility dictionaries before N39 recipes/mining.
- Abandoned facilities are already excluded from N39 recipes/mining. Observer now displays condition and abandoned status from live N39 snapshot.
- N39 snapshot/checkpoint persists these facility fields; N158 JSON restoration normalizes integer abandon_counter; schema checks bounds.
- No invented station Tools: N156 repair candidates have zero owned Tools until true ownership and paid repair are wired. No fictitious wage receipts.
- Remaining: paid repair with station-owned Tools, dock queues, crew morale, facility restock, full fleet, longer-run source parity.
- Static verification: re-fetched all six edited scripts from GitHub; balanced parentheses/brackets/braces. No Godot executable available; **WIRED_CODE_UNVERIFIED**.
- No GitHub Actions or Windows export triggered. No local runtime/GUI/save-reload verified.
- Risk: decay now happens before paid N39 production on every tick; check user F5 long-run condition values and save/reload before claiming parity.
- Rollback: revert six code commits above (in reverse order); no migration of frozen source JSON required.
- Lease `20261113-1439-lifecycle-automation11.json` to be RELEASED; all files free.
- Next: verify via Godot F5 or wire real station Tools inventory plus N39 paid repair Apply without duplicating ledger.

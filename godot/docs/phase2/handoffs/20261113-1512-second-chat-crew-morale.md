# P2 N156 crew welfare — 2026-11-13 15:12 MSK

- Shared PR #249, branch `integration/godot-phase2-unified-20261113`.
- Commits: `b014d364` (N156 bridge) and `f53ce7ba` (N39 canonical apply).
- Gate 1: N156 facility crew morale derived from previous **actually paid** N39 WorkShift workers and N151 household food satisfaction.
- N39 `work_shift.workers` dictionary is translated into frozen N156 tuple pairs, sorted by population ID; unmatched workers fail closed.
- Frozen N156 `start_tick` computes weighted morale at its exact 5×multiplier cadence; resulting morale is applied in the SAME staged N39 world as condition/abandonment before production.
- No second Food consumption, no second money ledger, no new TickRunner or save store. Existing N39 world snapshot persists `morale` (already validated in schema).
- Observer already displays N39 facility condition; morale is available through `economy_snapshot()` and `work_shift` debug inspection, not yet separately visualized.
- Checks: both modified scripts re-fetched; delimiters balanced; Godot 4.7.2 executable absent locally. **WIRED_CODE_UNVERIFIED**, no Actions.
- Risks: paid-shift workers may be absent until first N39 employment refresh; N156 then intentionally leaves morale unchanged. Check live F5 after paid shift and save/reload; no verified runtime behavior claimed.
- Next: integrate station-owned Tools and paid repair receipts; ensure no market-stock ownership confusion. Alternatively Gate 2 fleet if another worker owns repairs.
- Lease `20261113-1512-second-chat-crew-morale.json` released; both code paths free.

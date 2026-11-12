# N141 — строительство: оплаченный труд и общие резервы работников

**Macro #6, Фаза 1, CODE_UNVERIFIED.** Frozen source: `native/crates/sim_core/src/agents/construction/labor.rs` (whole `work/commit`), `agents/facility/workforce.rs` (`occupied_workers`, `refresh_employment`, `WorkShift`), `agents/construction.rs` (site/labor state), `agents/construction/executor.rs::present` (external attendance requirement). Source SHA `6e40615be95cc6ddbabe21c3b94def5c52f8622d`.

## Ported behavior
- Materials must be delivered first; completed sites and duplicate or later-tick shifts are rejected.
- Up to 10 worker-shifts per tick, bounded by remaining required labor, sponsor treasury and locally available workforce; 1 credit per worker. Partial shifts allowed; zero available workers rejected.
- Workforce availability: `floor(population * 3 / 5)` less same-tick durable facility, construction and commander shift reservations. Candidate households sorted by stable ID.
- Only same-faction, same-location households eligible. No synthetic employees, treasury or money.
- Preflight rejects negative household balance and signed-64 overflow before *any* money/state mutation. All changes applied to deep-copied state; sponsor debit exactly equals sum of household credits.
- Durable `last_shift` includes tick, workers, wages, zero processing/input fees, empty recipe output counters, and `last_executor`. Failure sets `blocked_reason` except `already_worked_this_tick`, which leaves original labor state intact.
- Recompute `employed_fraction` from the real shift receipts for **all** households after a successful shift.

## Explicit contracts / Phase 2 handoff
The caller supplies an **authoritative snapshot** with site, sponsor faction, households and all three shift-receipt sets, and a validated `executor_id` from Rust-equivalent `executor::present` (active Construct BT leaf, engineering-capable ship physically docked at non-abandoned facility). A nonempty string alone is not proof of attendance: the caller MUST validate it. Snapshot application must occur in the same atomic economic frame as facility production; run production first as Rust does, then construction. Never independently invoke this shift twice, and do not separately pay N77's labor receipt: N77 only accepts already-funded receipts. The resulting `last_shift` is a durable receipt, not a production recipe tick.

This module does **not** perform site materialization, station orders, contract escrow, facility recipe production or ship AI selection. Those are distinct source scopes (N77/N91/N39/N135). It returns a staged world state, which must be committed as a single transaction; no shadow ledger.

## Static review / limitations
Frozen Rust functions and their tests were read. Minimal syntax/delimiter check only; **Godot parser/runtime and Rust parity fixtures NOT executed**. GDScript int64 arithmetic assumes valid nonnegative population counts; extremely large populations beyond signed 64-bit are not a supported snapshot. The Rust implementation uses i128 in the workforce capacity expression. Phase-2 adapter must preserve precise wide arithmetic or fail closed for such data. No P1 integration, no merge.

# P2 N151/N114 — actual native abstract population migration in one World (14 Nov 2026)

**PR:** https://github.com/Mefits/Living-Sector/pull/249
**Starting HEAD:** `304d2d63c18878df24e6841dd7f2fc7ef9312201`.

## Actual code integrated
- The existing source `n151_native_population_migration.gd` is reused by `unified_population_phase.gd::migration_proposal`. One pressure-triggered move only at frozen Rust `agents/population.rs::run_population_migration` cadence `tick % (200 * tick_multiplier) == 0`, after N151 paid consumption/sentiment. Reads real N39 households, current sentiments, pressure, construction_dock status, real populations and balances; deterministic sorted household identities for save/restart.
- `n39_native_world_production.gd::apply_native_population_migration` recomputes from the sole authoritative current N39 World, stages all population mutations and one N9 household-to-household **real** wealth transfer where transfer amount >0. Validates conserved headcount and wallet amounts, no other household mutation, one immutable N9 operation ID `n151/migration/<tick>/<src>/<dst>`, exact account/World correspondence and total credit conservation before one in-memory swap.
- Zero-wealth movement does not generate a fictitious ledger transfer; it still persists the real migration event and denies replay at same tick. `population_migration_last` event is optional for legacy checkpoints.
- N39 schema checks both real identities, locations, headcount, event tick and linked N9 ID. N38 restore explicitly checks matching exact N9 receipt/legs when wealth moved (and rejects future event time).
- `n158_production_runtime.gd` invokes actual N39 migration only when N151 source `due.migration` is true, on the same tick and after paid population phase. The reader can inspect `population_migrated_this_tick`, `population_migration_credits_this_tick`, and persisted `population_last_migration` in its summary. The detailed N20 «Население» tab shows only actual committed transfers.
- `godot/tests/p2_n151_population_migration_paid_check.gd` added: original native source projection with explicit test-only adjusted demographic sentiments/balances, 200 native N39 ticks, one transfer 100 people and proportional household wealth, N9 receipt, full N38 save/restore, duplicate denial and tamper rejection. This is ONE integrated regression gate, **NOT EXECUTED**.

## Truth and limitations
- **WIRED_CODE_UNVERIFIED**; static balanced syntax/quotes and preloads on 6 files PASS. **Godot 4.7 executable NOT available in this worker; GitHub Actions=0.** No claims about visible runtime.
- Native `run_population_migration` is an original Rust **abstract demographic pressure migration** between established households. It does NOT create passengers, send N14 ships, create N151 colony docks, found new colonies or satisfy the previous user-observed zero N104 contracts at tick 212. The separate physical migration N147/Passenger/escrow remains a blocker.
- Rust ECS query order tie-breaking differs from our stable lexicographic canonical N39 household keys when pressures/sentiments tie; keep determinism and document parity edge.
- On a clean new seed (3 households, ~200 residents each, initial pressure 0) this migration only occurs after actual dissatisfaction and population >300; no artificial early move. At default tick multiplier 32, next possible tick interval is 6400.
- Next highest integration priority remains one real native N104 freight shipment on user-local Godot and N151 colony founding + physical N104 Passenger Apply; avoid frequent GitHub Actions.

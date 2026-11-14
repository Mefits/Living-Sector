# 14 November 2026 — N150 faction relations & BodyTerritory integrated (SOURCE-WIRED)

**User order supersedes old gates:** complete transfer of ALL Rust Galaxy 0.6.7 code into the unified Godot project first. Only AFTER the last integration block will the user test and submit balance/mechanics changes. Do NOT request intermediate tests, certify a partial gate, alter balance, or run CI per block.

## Real work in PR #249
1. `unified_native_diplomacy_phase.gd` bridges source `n150_native_full_faction_relations.gd` and `n150_native_market_territory.gd` against the physical N39 World and original orbital body IDs.
2. Frozen Rust faction taxation/control cadence: territorial ownership derives in **factions** phase every `50 × multiplier` (source `agents/faction.rs::TERRITORIAL_RECOMPUTE_INTERVAL_BASE`) from actual non-gate, already-built facilities, each body's credit-weighted tie rule and system rollup. `body_territory` persists as one N39 ECS projection with original default non-owner/noncontested records on all 47 frozen bodies. N9 untouched. N39 rejects duplicate applies.
3. Rust `engine.rs::relations` is a distinct late phase. It advances the canonical symmetric treaty matrix every `200 × multiplier`; the stored pair records and phase cursor survive N38. New clean seed has no explicit pairs (source Neutral defaults); old saves lacking the pair domain are NOT silently backfilled. Any explicit pair must reference real faction treasury IDs and valid timestamps.
4. N97 paid source pickup consults frozen `faction_relations::commerce_allowed` using real location market controller majority. Hostile/War fails before paid physical N15 transfer; same/neutral trade retains original N97 price/reputation flow. No fake treaty events, standing increases or ships.
5. N158 economic summary exposes derived system/body/market controllers and actual treaty state. The first real source-capable N134/Hyp planner can now read territorial control and matrix from the single N39 World instead of a shadow.

**Static delimiters and all native preloads checked on 6 changed GDScript files — PASS. Godot NOT executed, Actions=0 by explicit user request to defer testing until all integration is complete.**

## Still not integrated
- Native N129 `run_tax_cycle` / `run_bailout_cycle` and full `relief::tick_relief` into authoritative N9 transfers.
- Source diplomacy events from actual breaching/delivery changes (do NOT synthesize standings just to make them vary).
- N100 faction-head strategic subsidy planning, N154 paid shipyard/refits and N151 real colony life cycle.
- Full source+GUI integration remains OPEN. Do not count this as a runtime-verified gate.

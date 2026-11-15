# Chat №3 / N113: original research, expansion, prior-supply strategic candidates

**2026-11-14 · shared PR #249 · `integration/godot-phase2-unified-20261113`**

## Source evidence

Frozen Rust `native/crates/sim_core/src/strategy/coordination.rs::run_cycle` and `strategy/director.rs::retain_or_switch` build one ordered collection: source supply option_score, research only if `director::research_ready` (18×science, incumbent +2, delegated research charter priority), expansion existing active site 80 or new site 25×expansion, migrant source offer 60, and re-quoted previous supply from `options::compare_director_target`. N113 superior alternative 1.20× over 2 real decisions, without breaking prepaid N104/HTN plans. N147 may publish one real paid Passenger only if current faction Head authorizes migration.

The prior Chat3 N113 pass had copied the 1.20×/two-cycle mechanism and current N134 Build/Deliver score but **conservatively blocked all previous research, expansion and different-supply commitments**, because their source readiness could not be verified by the narrower N134 construction-only adapter. This iteration reconnects the actual already-ported native domains instead of synthesizing a second strategy engine.

## Implemented in shared branch

- `98be835`, `412335d`: new `godot/scripts/sim/phase2/unified_n113_original_candidates.gd`. **Pure, read-only projector over same N39 World**. N143 source: `NativeResearch._population_rows/_market_rows` + N141 `Payroll.occupied` + `ResearchShift.research_ready` + original 18×science, research incumbent +2; no fabricated electronics, people or treasury. N144 source: original active-site N104/Metals/dock route via `NativeColonyContracts.active_site` plus physically proven new planet via `NativeNewColony.propose`, score 80 active / 25×expansion new. Previous DIFFERENT supply: `NativeConstruction.observe` / N134 `_forecast` / N111 `compare_goal` / N155 frozen `option_score` on real market+source N154 offer. An old supply target with no **positive** construction quote is **NOT** treated as extinct because N135/N121 may still have an outstanding logistics path not observable from N154; it remains unresolved and retains its source commitment.
- `1e06987`, `fab3a5c`: `unified_n147_colony_head_grant.gd` takes optional real `sources/original/graph/multiplier`; merges true N143/N144/N111 candidates into the SAME source N113 utility comparison. Duplicate current N134 quote not counted twice. Unknown prior source supply remains protected. If selected outcome belongs to a newly elected non-migration Head, N147 does **not** post a faux paid research/expansion action or overwrite that Head's authoritatively owned decision; real owning phases still govern. N147 migration is admitted only by the one source utility decision.
- `fd7070f`: existing `n39_native_world_production.gd::post_native_passenger_migration` passes its ONE source `World/sources/original/graph/multiplier` to the pure N113/N147 comparator. The earlier N39 atomic N113 pending/actual N104 escrow split remains intact; no duplicate ledger, contract board or clock.
- `822d567`: N113 source helper now supports explicit `cycle_stride` for sparse N147. Missing a real intervening 60×mult decision (because no migration offer was available) **resets** first-cycle pending rather than accepting two nonconsecutive opportunities; repeated same-tick confirmation still rejected.
- `7e6294b`: expanded deferred `p2_n113_strategic_switch_check.gd` with adjacent and skipped actual strategic cycle.
- `375ab2e`, `f2d4da6`, `4bc6353`: new deferred `p2_n113_original_candidates_check.gd`: real-shaped canonical N39 research readiness baseline 18×1.5+2, strict treasury reserve >, Electronics absent, workers absent, Director crisis, no-phantom N144 colony with empty bodies, full source projector paired candidate result, original World immutability, unresolvable previous supply protected. **Authored, NOT RUN**.
- `890d6b9`: updated the single offline `godot/tools/p2_v4_source_gate.py` to check N143/N144/N111 source candidate links and the new adjacent-cycle marker (the previous string matcher had become stale).
- `e76decf`: updated `godot/docs/phase2/P2_V4_FINAL_ACCEPTANCE_MATRIX_RU.md` from the current source state.

## Exactly what remains

**SOURCE_WIRED (N143 research / N144 expansion / N154 and N111 source-positive previous supply) / CODE_UNVERIFIED / RUNTIME_UNVERIFIED.** Eight changed files fetched again from latest shared GitHub HEAD: all GDScripts balanced parentheses/brackets/braces, no odd quote lines, NUL absent, newline present. **NO Godot parser, headless, F5, Windows, Actions or deferred test execution** (single final full integration gate per user). No gameplay balance/logic retuning.

**Not equivalent yet to the complete Rust `coordination.rs`:**
1. Delegated player charter/research priority addition and authorized `accept_authorized_player_priority` remain owned by original governance N109/N110/N143 and require comparison against live mandate, not an invented override. The currently active P2 N143 research adapter supplies empty mandate/charter, so this projector matches **the actually wired P2 research path**, not every frozen Rust governance configuration.
2. Old supply goals provided by original logistics N135/N121 but missing an N154 construction offer are deliberately **unresolved**. Never mark them unavailable to allow migration prematurely, nor synthesize arbitrary profit.
3. Cross-category decisions to newly chosen *nonmigration* science/expansion Heads are not commissioned from this N147-only adapter: it does not own real N143 research shifts or N144 paid colony grants. Full N113-wide Head source authority remains a broader integration issue. Source N147 allows only its validated migration action.
4. When N147 has no ready original physical passenger offer on a strategic cycle, N147 itself does not run N113. The `cycle_stride` guard ensures its pending counter does not skip absent real cycles; it is source-safety, not proof that global leader strategy selection runs every original Rust decision cycle.
5. Need genuine N38 between-cycle save/reload, real continuous source N147 passenger embark/delivery/N9 paid, original N21/N84 dock timeout and whole-game Godot/Windows acceptance.

**Coordination:** Chat1's N21 FIFO lease was RELEASED at block start, and a new separate Chat1 N21 dock timeout lease later became IN_PROGRESS. Chat3 made **zero changes** to N158, N21, fleet logic or Chat1's reserved files. Only the specific already free N39 N147-context call changed. No GitHub Actions triggered, no tests run.

**Next safe step:** one final source-level policy/Head ownership audit for player-directed N109/N110 and N135 previous supply, then establish `SOURCE_INTEGRATION_COMPLETE` only after genuine gaps close. At that point perform *one coordinated* Godot 4.7.2 script/parser A/Б/В/Г + Windows x64 acceptance, not repeated microtests.

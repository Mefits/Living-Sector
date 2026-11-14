# 14 November 2026 — N154 authentic shipyard module production into one N39 World

**User directive:** finish the entire Rust-to-Godot source integration first; no intermediate playable tests or balance/mechanic/UI changes. PR #249, shared branch `integration/godot-phase2-unified-20261113`.

## Integrated code
- N39 facility production now calls `_run_shipyard_modules` on the exact frozen `15 * tick_multiplier` cadence, after existing paid recipe/mining work. Actual source `n154_native_shipyard_module_tick.gd::plan_one/after_paid_shift` and original N132 T2/T3 recipes are reused.
- Only genuine built, active `shipyard` facilities at a real source market are considered. The frozen new-game Galaxy has **0 shipyards**; there is no free shipyard or extra module at startup.
- At most one understocked module per shipyard per due tick. Exact source recipe inputs + actual local posted market prices or frozen `Commodity::base_price`. Each candidate requires `Payroll.pay_shift` on real N39 households and ONE N9 ledger (wages and paid producer-input fee to the same physical stock owner). Only after the paid shift receipt does native `after_paid_shift` subtract physical market inputs and increment facility-local `module_stock`.
- N39 stages the World and N9 Ledger together; source stock, all wallets and money totals are checked before the single commit. If the shift is not funded, NO goods or modules are created. Native 200/50-tick diplomatic/faction-finance phases remain in their original order.
- N39 schema validates optional `module_stock` on the actual shipyard only (original N132 slugs and nonnegative u32 quantities), preserving in the existing N38 checkpoint; older facilities/saves lack it legitimately. N158 economic summary exposes truly paid module batches and real blocked candidates.
- No new resource formulas, ship stats, starting money, ship/facility actors or player commands.

## Next dependent source block
- Native N108/N51 refit + ship progression must be brought into the **canonical N46 ShipState** first. Current physical `ship_state.gd` has cargo/fuel/route but no full `ShipFitting`/retrofit-points representation; frozen 24-ship bootstrap explicitly rejects non-comms fitting changes. Therefore **NO ship refit is claimed from this module production commit**. Integrate source `n154_native_paid_shipyard_refit.gd` / `n108_shipyard_refit_apply.gd` after upgrading exactly that representation and making N14/N153 read native derived speed/cargo.
- Other open blocks: N100 head/admin active AI, N151 real colony/nav/paid passenger flow, source remaining crises/events/piracy and all-program final integration. No source-only completion should be called verified yet.

**Verification:** targeted static source checks only (delimiter/quote/import) PASS on three modified GDScript files. Per explicit user order, **Godot not run, no Actions or gameplay tests** until full transfer is finished. Integrationally wired but NOT a runtime PASS.

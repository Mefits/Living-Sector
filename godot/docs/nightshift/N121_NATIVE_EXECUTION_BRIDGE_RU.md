# N121 — большой перенос native_execution.rs: HTN → реальные заказы, квитанции, оплаченное производство

**Дата:** 12 ноября 2026. **Фаза:** 1, покомпонентный перенос замороженной Rust Galaxy 0.6.7. **Резервация:** атомарный `feature/godot-nightshift-20261112/godot/docs/nightshift/claims/N121.json`, SHA `abf9dd3f1883da59700fdded7e4497cf065c60fc`. Ветка `feature/godot-n121-native-execution-20261112` от `integration/godot-47-n33-n37-20261112`. **Статус:** `CODE_UNVERIFIED`. Godot по решению пользователя не запускался; общая сборка и прогоны назначены на фазу 2.

## Зачем этот крупный блок

В отличие от GOAP, HTN, Utility и Beam, здесь нет нового выбора целей. Frozen Rust `native/crates/sim_core/src/strategy/planning/native_execution.rs` (~61 КБ включая тесты) превращает уже выбранный план в реальные **обеспеченные деньгами контракты** и ждёт подлинные квитанции от `ContractBoard` и `FacilityCrew`. Выбор плана, подписанный приказ и завершающий эффект — разные вещи. Нельзя засчитать оплату только по публикации объявления, нельзя засчитать товар по прогнозу производства, нельзя повторно предъявить Prepare после загрузки сохранения.

Исходники для сверки:
- `strategy/planning/native_execution.rs`: `NativeExecution`, `NativePlan`, `NativeOutcome`, `DeferredGoal`, `same_stock_goal`, `is_urgent_preemption`, `select_stock_goal`, `retryable_native_failure`, `next_retry_delay`, `record_planning_failure`, `record_deferred_goal`, `output_counter_key`, `output_counter_value`, `produced_goal_units`, `active_production_priority`, `unique_market`, `unique_global_market`, `native_goal_stock`, `contract_receipt`, `production_receipt`, `native_production_baselines`, `post_native_delivery`, `drive_native_htn`.
- `strategy/planning/ledger.rs`: durable `PlanLedger` transitions and `PlanGate`, independently ported **N98** ([PR #186](https://github.com/Mefits/Living-Sector/pull/186)).
- `strategy/planning/native_catalogue.rs` and `strategy/planning/hybrid.rs`: physical candidate/recipe provenance and action catalogue; hybrid planner currently owned by **N100** ([PR #188](https://github.com/Mefits/Living-Sector/pull/188)).
- `economy/contracts.rs`: real subsidy `post_subsidy`, prepaid `register_prepaid`, `station_order=Order::new("htn", dispatch_key)`, board IDs/indexes.
- `strategy/orders.rs`: exact stable `station:htn:<dispatch_key>` ownership.
- `agents/faction.rs`: `SUBSIDY_CHECK_INTERVAL_BASE=60`, `SUBSIDY_LIFESPAN_BASE=500`, `FACTION_SUBSIDY_FLOOR=5000`.
- `agents/facility/mod.rs`: `RECIPE_INTERVAL_BASE=5`, real paid work shifts.
- `strategy/sourcing.rs`: physical purchase quotes, own-faction market fee 0.75, rechecked on final ship purchase.

## Новые файлы

### 1. `godot/scripts/port/n121_native_execution_state.gd`

Pure read/write copies of durable `NativeExecution`:
- `active`, `blocked_until`, `deferred_goals` and bounded 64-entry terminal `history`;
- identical stock goal even if `target_units` changes; emergency Food/Water goal or a >25%+1 priority jump can preempt deferred need;
- at most 3 attempts, source cooldown `120 × max(mult,1) × 2^min(attempts−1,3)` ticks; after permanent failure do not carry stale dispatch key, price or route;
- a completed goal removes retry/cooldown, but retains physical closing stock and durable receipts in history;
- stable output counter key `action_id::output:commodity`; unqualified legacy action ID may be read ONLY for original `action.commodity` (not by-products);
- `produced_goal_units` based on accounted paid counters, not forecast; read-only active production priority for the exact current recipe, not only final target.

### 2. `n121_native_receipts.gd`

- `unique_owned_market` must select exactly one faction-owned warehouse at a location, `unique_global_market` additionally ensures it is the only **world** market at that location (foreign co-located market cannot hide).
- Contract `Posted→Submitted`, `Accepted/PickedUp/Delivered→Running`, `Paid→Succeeded`, `Expired→Failed` **only after remaining escrow was really refunded**. Don't regress Running to Submitted on stale posted snapshot; never replace current native order identity.
- Production `Produce`: exact pinned facility/recipe, real paid shift newer than plan creation, world market uniqueness, every recipe output advancing separately by its positive recipe quantity. ProcessIce water AND fuel both checked. Same counted output cannot be credited twice.
- Legacy snapshots without qualified counters: a paid shift plus **every actual output visible in the true market** may confirm one recipe instance, but no credits are added to cumulative counters and another instance of the same recipe cannot reuse it.
- Wait timeout `5 × RECIPE_INTERVAL_BASE × max(mult,1)` after `production_started_tick`; return fail receipt, not new fabricated stock.
- Crucially returns `receipt` and `accounted_after_ack` as **intents**; update counters only when N98 accepts receipt atomically.

### 3. `n121_native_dispatch.gd`

Native physical delivery `post_native_delivery` preflight requires:
- actual Deliver action with positive units/credits; source and destination genuinely different;
- two unique native faction markets, and both globally unambiguous; exact action ID `htn-preview:deliver:<source_market_id>:<destination_market_id>:<commodity>:<units>`;
- source has enough real units; valid source market price or original base; source purchase cost less than approved contract reward; source-priced quote remains checked at the real N97 Apply;
- actual navigable source→destination route (no invented distance), one faction-owned idle carrier physically at source, no transit, capacity, fuel, enough own credits to purchase, no other held contract;
- no open existing contract for same faction/destination/commodity, treasury remains ≥5000 after reward, no duplicate dispatch key; one funded strategic contract per faction/tick enforced by driver;
- on success staged whole-world `treasury -= cost`, creation of `contract-(next_id+1)`, status Posted, Subsidy, actual reserved faction escrow and `station:htn:<dispatch_key>` order, all `ContractBoard` status/destination/faction indexes included in same staged copy; NO resource stock changed.
- Return same precise source rejection reasons for retry classification; wrong/ambiguous/absent data always rejects rather than inventing a payer.

**Precision caution:** Rust calculates `purchase_cost` using f32 quoted price/multiplier and then f64/ceil. GDScript uses double and cannot claim bit-identical boundary behavior for extreme values. Final economic Apply (N97) must recheck at settlement.

### 4. `n121_native_driver.gd`

Main `drive` state machine:
- explicit opt-in `htn` or `hybrid`; default original director fallback;
- one selected head stock goal, optional deferred retry, opportunity for emergency preemption and cooldown;
- planner N93/N100 provides a fresh source-validated candidate, N98 provides valid PlanLedger+NextGate. Driver does not implement a competing planner or issue new recommendations;
- `Completed`: only marked complete after **actual** goal stock (unique real market), or genuine paid output counters for production milestones even if citizens consumed it;
- `NeedsReplan`, `AwaitDependencies`, `ReconcilePrepared`, `AwaitNative`, `Ready` retained separately;
- Prepared on reload NEVER resubmits. Looks for existing `station:htn:dispatch_key`, otherwise blocks as `prepared_order_not_found_no_duplicate_dispatch`;
- `AwaitNative` obtains only real board/paid-recipe receipts; emission as `ledger_ops` for N98. Once payment rejected or timed out, terminal outcome + cooldown does not grant stock.
- Ready Deliver calls `post_native_delivery` only once per source cycle; Ready Produce prepares a passive `facility:<id>` observation — **never issues a fake produce command**.
- Staged world+board+N98 prepare/ack must be published **one atomic checkpoint** in Phase 2; without N98 confirmation this PR does NOT assert a committed delivery.
- Reports preserve Rust `native_hybrid_opt_in` vs `native_htn_opt_in`, planner rationale, stable plan ID, reason, order ID and actual committed credits.

### 5. `n121_native_production_baselines.gd`

Reads **real** `FacilityCrew.work_shift.produced_outputs` per pinned exact facility/recipe, records every product qualified counter at plan creation. A missing old counter is NOT evidence of zero stock and needs strict paid-shift/visible-product fallback.

## Переход к фазе 2 — строгое объединение

- N121 independent of N98/N100: **НЕ добавлен preload на чужой незакреплённый файл**; exposed `ledger_ops` must pass through N98 PlanLedger and its exact permitted transitions. When a paid order is created, N121 world+board and N98 ledger must COMMIT OR ROLLBACK TOGETHER under one exclusive tick. Status `CODE_UNVERIFIED` until that works.
- Original Rust `PlanningSnapshot.capture` and `native_catalogue::pinned_producer_recipe` need normalized authoritative `snapshot.owned_markets`, `world.global_markets`, `world.producer_recipe_pins`, `world.facilities`, `world.nav_shortest_distance`. Values are **data source contracts**, not generated by N121.
- Shared treasury N11, real ship transactions N97, contract escrow/delivery N104, N39 production and N116 paid work shifts are mandatory single owners. N121 **only** authorizes a new sourced delivery order and verifies already observed output; no production, fuel, salaries, treasury minting or new GOAP pathfinding.
- Live N100 Hybrid logic and N93 HTN stay independent, and verified P1 remains untouched. Common full Godot assembly + full end-to-end run deferred to phase 2; Grok improvements only phase 3.
- Future source parity investigations needed: exact Rust f32 price/quote rounding and >2^53 integer boundary; old checkpoint migration, exact order index serialization and ledger atomicity after recovery. These are **known unverified boundaries**, not silently declared complete.

## Короткая проверка без запуска Godot

Only static source/formula review; every new GDScript file and its local `res://` preload paths exist, source `SUBSIDY_CHECK_INTERVAL_BASE`, `SUBSIDY_LIFESPAN_BASE`, `FACTION_SUBSIDY_FLOOR`, `RECIPE_INTERVAL_BASE`, `MAX_GOAL_RETRIES`, `MAX_OUTCOMES` verified; bracket counts + long-line review. No Godot runtime or repeated expensive integration tests now.

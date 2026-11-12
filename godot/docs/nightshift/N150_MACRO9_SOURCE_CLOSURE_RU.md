# N150 — закрытие исходного покрытия макро №9: рынки, дипломатия, территории

**Цель:** завершить существующие *реальные* Rust-алгоритмы для фракционных отношений, рынка и контроля территорий в независимых GDScript-компонентах, не собирать всю игру в Phase 1.

**Состояние:** исходный домен макро №9 **SOURCE-COVERED across existing N68/N69/N115/N122/N124/N129/N131/N136 + N150** с ограничениями ниже; весь код **CODE_UNVERIFIED**. Это **не утверждение**, что любой реальный market ship может сейчас купить/продать товар в Godot. Сборка World и реальные транзакции — в Phase 2. Резервация `claims/N150.json` на общей `feature/godot-nightshift-20261112` создана **перед кодом** (commit `95a38347`). Изменения только в `feature/godot-n150-market-diplomacy-territory-complete-20261113`; frozen Rust 0.6.7 `archive/rust-galaxy-067-reference`.

## Аудит исходников и принятые владельцы

| Frozen Rust source | GDScript-покрытие после N150 | Важная деталь |
|---|---|---|
| `agents/market.rs::MarketPricing.price`, `MarketFlow`, `MarketOrders`, `MarketHistory` | **N150 `n150_native_full_market_tick.gd`** | original base-price lookup injected from source `Commodity.base_price`, остальные data-domain fields сохраняются |
| `agents/market.rs::record_consumption` | N150 `record_consumption` | в rolling window пишется только **реально известное** потребление; нет нового события покупки/еды |
| `agents/market.rs::tick_markets/tick_one_market` | N124 [PR #212](https://github.com/Mefits/Living-Sector/pull/212) (упрощение demand) + **N150 FULL market state** | одна исходная смена: инициализация seed, demand по rolling window и warmup; каждые `max(1,mult)` сырых тиков — shortage+price, raw tick %16 — настоящий trend ring 200 точек; remove anonymous market orders, expire orders; не придумывать stock/credits |
| `agents/market.rs::MarketSnapshot::build` | N150 `wire_snapshot` | цены, предложение, спрос, shortage и наблюдаемые trend prices+supply, только read-only; не формат сохранения ECS |
| `economy/price_engine.rs::{recalculate,apply_spread}` | N68 [PR #157](https://github.com/Mefits/Living-Sector/pull/157) + **N131 [PR #220](https://github.com/Mefits/Living-Sector/pull/220)** | N150 **не дублирует** формулу; `tick_one_market` принимает валидный Callable к исходному N131 `recalculate`; нет второго PriceEngine или второго владельца цен |
| `sim_server/engine.rs::scan_crisis_events` — **market branch** | **N150 `n150_native_market_crisis.gd`** | events `market_crisis`/ `market_recovered`, hysteresis, thresholds из N140 WorldTuning; ветвь **facility_starving** относится к макро №1 и не выдается за market |
| `agents/faction_relations.rs::FactionRelations`, `RelationState`, `TreatyKind`, `bump_standing/set_treaty/set_state` | N69 [PR #158](https://github.com/Mefits/Living-Sector/pull/158), N115 [PR #204](https://github.com/Mefits/Living-Sector/pull/204) + **N150 `n150_native_full_faction_relations.gd`** | canonical lexicographic pair, state-or-default, clamp −100..100, same treaty does not reset since_tick, but **new neutral pair still created**; zero self updates |
| `faction_relations.rs::tick_relations/next_treaty`, `engine.rs::tick_relations_pass` | **N150** | caller cadence **200×max(1,mult)**; grace **2000×max(1,mult)**; decay 1 toward zero, deadband ±1; pact threshold 50/500 ticks; allied 75/1000; tense −50, hostile −70, recovery −20/−40; war sticky/manual only; treaty transition **does not refresh** last_event_tick |
| `faction_relations.rs::trade_pact_dock_modifier/payment_multiplier/grants_visibility/treaty_rep_floors` | N69/N115 parts + **N150** | returned pure factors/rep floors; real Dock/Contract Apply remains external, grants nothing |
| `faction_relations.rs::market_controllers, commerce_allowed, own_market_priority, market_buy_multiplier, market_sell_multiplier` | N115 partial + **N150** | market controller by owned facility count **including gate facilities**, lexical-smallest tie; Hostile/War blocks commerce, ship-specific rep affects price at actual physical trade point only, market posted price not rewritten |
| `agents/celestial_body.rs::derive_territorial_control` | N122 [PR #210](https://github.com/Mefits/Living-Sector/pull/210) + **N150 `n150_native_market_territory.gd`** | Unlike market controller, **gate facilities excluded**. Body chooses most real facilities, then total owned credits; contested when 2+ factions. System tallies body controllers only; tied system => **None**, no fake owner |
| `agents/faction.rs` tax/treasury interactions | N129 [PR #218](https://github.com/Mefits/Living-Sector/pull/218) + other macro #1/7 source | No second ledger or universal tax in N150 |
| `strategy/economic_proposal.rs`, market purchase/review authorisations | N136 [PR #224](https://github.com/Mefits/Living-Sector/pull/224) | Retail purchase actually moves money/goods via **макро #5** and paid production via **№1**, not N150 |
| `agents/celestial_body.rs::tick_bodies_regen`, biome/resource richness, `BodyOrbit` | Body ecology N123 and movement/planet sources **макро #2/10** | Environment and UI positions, NOT ownership/market exchange; do not call missing territory logic |

### Точные правила, которые старые порты не охватывали

1. **Рынок** в frozen Rust НЕ работает как старый Elixir MarketAgent 8-phase в комментарии. Реальные production/consumption уже физические в `Facility` / `Population`; `tick_one_market` лишь наблюдает и пересчитывает, анонимные ордера `market-*` удаляются **без перевода денег**. N124 не покрывал `MarketHistory.trend_samples`, `MarketSnapshot` и полный native source tick. N150 делает source-facing полный one-market stage, а фактический price calculation делегирует N131.
2. **Дипломатия** в N115 по большей части содержит переходы, но её `tick_relations` нельзя просто вызывать каждый физический тик: в настоящем Rust это редкий pass `200×max(1,mult)`. Источник применяет freshness-guard, decay и treaty ladder **только на этом ритме**, не на каждом callback. N150 переносит эту границу и полноту treaty consumers.
3. **Рынок и территория** НЕ имеют одинакового определения владельца: `market_controllers` голосует по всем объектам `FacilityIdentity` на одной локации, **включая врата**. `derive_territorial_control` исключает `facility_type=gate`, суммирует кредиты при равенстве количества построек и позволяет `None` для неосвоенных планет и системных ничьих.
4. **Тонкость настоящего исходника**: в `derive_territorial_control` при строго равных количестве построек и сумме кредитов у двух фракций сортировка Rust не вводит последний лексикографический tie-break (порядок зависит от HashMap). N150 выбирает стабильную лексикографическую фракцию **и честно возвращает диагностический список** `original_rust_undefined_equal_credit_ties`. В остальных сценариях соответствует исходному ранжированию. Перед названием *битовой* parity в Phase 2 следует утвердить явное tie правило либо сохранить неопределенность оригинала.
5. **Кризисы** не создаются рыночным тиком: отдельный `scan_crisis_events` использует `WorldTuning`. Уровни оповещения могут быть изменены, но события эмитятся только при входе/выходе из зоны критической нехватки.
6. Нельзя сохранять `MarketSnapshot` как истину рынка, прибавлять supply из seed `production`, начислять бесплатные фракционные кредиты или открывать чужой trade без фактических отношений.

## Новые файлы N150

- `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`: полный staged market tick, sample/cooldown/demand/price (external N131) + `record_consumption`, read-only market JSON snapshot, source `MarketPricing.price` fallback.
- `godot/scripts/sim/phase1/n150_native_full_faction_relations.gd`: полный source FactionRelations canonical matrix и все treaty transitions + trade/dock visibility/controller factors.
- `godot/scripts/sim/phase1/n150_native_market_territory.gd`: точная body/system majority и contested, gate exclusion, диагностическая отметка неразрешённой в Rust ничьей.
- `godot/scripts/sim/phase1/n150_native_market_crisis.gd`: original crisis hysteresis и события по реальным MarketHistory.
- `godot/scripts/sim/phase1/n150_market_relations_territory_checks.gd`: подготовленные **не запускались** source-derived сценарии для полного scope.
- `godot/docs/nightshift/N150_MACRO9_SOURCE_CLOSURE_RU.md`: этот документ и границы владельцев.

## Фаза 2 — единственные настоящие владельцы эффекта

**Market:** authoritative ECS MarketIdentity/Pricing/Flow/Orders/History → N150 `tick_one_market`, injected **N131.recalculate** (загруженный из его отдельно созданного draft PR) → **один** real market commit. N68/N124/N150 `tick` НЕ вызываются вместе; источник один. При каждом real paid consumption `record_consumption` передаётся текущий физический товар/qty/tick. Market price is not physical trade debit.

**Diplomacy:** authoritative singleton `AgentStore.relations` → проверка `pass_due` → `tick_relations` в engine один раз /200×mult → event emission; direct setters/bump only from paid contract/admin world events. N69/N115 не являются вторыми singleton matrices. Потребители dock, contracts, ShipAI market posture читают только **этот** matrix, не собственную копию.

**Territory:** body identities + фактические `FacilityIdentity` и `FacilityOperations.credits` → N150 `derive` после реальных изменений имущества и строительства → запись `BodyTerritory` и derived `AgentStore.system_control`. Все HUD/AI читают одну проекцию. Никакой генерации физических объектов по карте. Реальные trade/ship contracts/escrow = макро #5; политика бюджетов/налогов = макро #7/#1.

**Verification:** все файлы GitHub readback; static quoted-string/bracket/preload/source-branch checks; fixture **authored but NOT run**. НЕТ Godot parser/headless/Windows, НЕТ Rust-vs-GDScript running replay, НЕТ объединения отдельных draft PR в один исполняемый World. Макро №9 закрыто **только по компонентному исходному покрытию первой фазы**. Точный общий процент Phase1 не вычисляется из числа PR.

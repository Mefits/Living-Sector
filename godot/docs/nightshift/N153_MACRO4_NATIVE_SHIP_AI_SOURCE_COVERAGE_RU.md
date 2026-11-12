# N153 — макроблок №4: автономный корабельный ИИ Rust Galaxy 0.6.7 → GDScript (Фаза 1)

**Статус:** `CODE_UNVERIFIED`, *source-domain mapped across prior PRs + N153*. Полноценная симуляция в Godot **не** собрана, паритет исполнения не подтверждён. Код живёт в отдельной ветке и Draft PR. Вторая фаза соберёт один authoritative TickRunner, а не четыре отдельных ИИ.

## Резервация и эталон

- Единственный новый claim: `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N153.json`, создан **до кода**, commit `e5de8c72ec749684fc29e6970ffc0313214c09c0`.
- Замороженный Rust: `archive/rust-galaxy-067-reference@6e40615be95cc6ddbabe21c3b94def5c52f8622d`. Основной файл `native/crates/sim_core/src/agents/ship/behavior.rs` (3351 строк), плюс `agents/ship/{mod,actions,components,transactions}.rs`, `ai/*`, `world/pathfinder.rs`, `economy/contracts.rs`, `strategy/orders.rs`.
- Рабочая ветка: `feature/godot-n153-native-ship-ai-behavior-20261113`, основание `integration/godot-47-n33-n37-20261112`, контрольный P1 и frozen Rust не изменялись.

## Уже существовавшее покрытие — нельзя применять дважды

| Исходная функция | Единственный первоначальный порт / место |
|---|---|
| `ai/personality.rs`, archetypes/drift; `ai/utility.rs`; `ai/considerations.rs` | N80 PR #169 / N85–N87 / N137 PR #226; фазе 2 выбрать **один** personality/utility/consideration owner |
| `behavior.rs::score_strategic`, tier goal/archetype weights; 40-tick per-id replan hash and ratio; idle-explore threshold | N80 PR #169; N153 mirrors the final goal arbitration but **must not run a second N80 scorer/scheduler** |
| `behavior.rs::choose_ice_mining_trip` and `profitable_mining_quantity` | N80 PR #169 + N103 PR #191; N153 accepts scored candidate (miner-class and unassigned only) |
| `behavior.rs::cargo_liquidation_target` | N103 PR #191: real buyer cash, prices, commerce, no infinite insolvent sell |
| `behavior.rs::best_trade_route[_with_ownership]`, `median_known_price`, `mod.rs::price_freshness_weight` | N83 PR #172, N137 PR #226. N153 adds original absolute 50-unit profit and BT request adapter, never duplicates route learning |
| `ai/planner.rs` full GOAP `WorldState` / `LocMap` / catalogs / bounded search | N81 PR #170 (native planner **single owner**); N153 prepares exact intent specifications only |
| `ai/behavior_tree.rs` stateful sequence/selector execution | N84; N153 converts action list to N84 leaves only |
| `agents/ship/actions.rs` dock/rest/undock/construct, economic requests | N88 PR #177 and N90 PR #182; N108 for paid gate/retrofit Apply |
| `agents/ship/mod.rs::advance_transits`, fuel/crew/ship life | N112 PR #201, N149 PR #238; retired ship strikes N148 PR #237 |
| `economy/contracts.rs`, `engine/transactions.rs` and funded Apply | N152 PR #241, N104 PR #193, N97 PR #192; N135 PR #225 assigned orders, no duplicate money or status mutations |
| Faction/controller/treaty/territory and route graph | N150 PR #239 / N59 / N61; N146 owns actual SimCommand ordering |

## N153: недостающий связующий исходный слой

| Rust функция, исходный диапазон | N153 файл/функции, проверяемое поведение |
|---|---|
| `behavior.rs::try_plan_contract` (1877–2228) | `n153_native_ship_contract_selection.gd`: assigned Posted bypass of public rep only, 2.0 sensor gate, all three hostility checks, payer/escrow/acceptance quote preflight from N104, 3× queued congestion gate, physical capacity, source price/upper median, gate-fee rough estimate, i64 wallet gate, delivery fill sqrt factor, own-strategy-first ranking, exact goal name |
| `contract_funding_key` (1284–1299) | same file `contract_funding_key_from_native_snapshot`: original debug-field composition; quote and payer Option/debug are provided by N104 |
| `try_plan_trade_run` (267–313) | `n153_native_ship_bt_planning.gd::trade_candidate_from_native_route`: uses N83 solvent route, source 50-unit f32 rounded profit, creates trade_run request |
| `build_*_bt`, `try_build_*_planned`, `estimate_fuel_bucket_cost` (2232–3122) | `n153_native_ship_bt_planning.gd::plan_request`: six Rust GOAP catalogs + exact goal flags/depth caps (16/20/28), real fuel bucket, Origin/Source/Dest/Shipyard cost map, combined delivery+retrofit and trade+retrofit |
| `resume_contract_bt` (2934–2982) | `resume_contract_request`: status/cargo-based resume, no Accept replay, physical loaded-state, passenger status, explicit courier missing-physical-cargo refusal, unchanged Board/escrow |
| `compile_plan_to_bt` (2983–3029) | `compile_plan_to_bt_actions`: N59 path leg→Travel/GateJump expansion, Dock/DockAtShipyard 2s dwell, Undock 2s dwell, AcceptContract exactly once, direct Travel fallback if no route |
| `pick_rest_destination`, `any_rest_destination_viable`, `contract_destination_is_saturated` (2469–2597) | same BT file: queue+docked 1.2 saturation, 3× queued contracts, same-system rest target, stays when free slot, skip all-saturated rest |
| `find_retrofit_opportunity` (2645–2710) | same BT file: exact slot priority engine/cargo/sensors/reactor/comms, tier+1, ship credits reserve 12000, in-stock at live shipyards, same location/system/other ranking |
| `smart_idle_fallback`, `try_build_explore_bt`, `pick_same_system_station` (1670–1833) | source trigger/scoring N80; N153 `explore_plan` walks current system paired gates/recent window then dock/dwell 5s/undock; idle station fallback when exploring fails |
| `plan_goal` (1320–1612) | `n153_native_ship_ai_pass.gd::build_goal_candidates`: bio rest/refuel, assigned order early return, housekeeping cargo/refit, contract/trade with contested + own-market preference + combo goal bonuses, N103 miner and N91 engineer arbitration, idle floor |
| `decide_and_act` (442–1182) | same file `decide_pre_bt/apply_bt_result`: LOD/transit gate, held contract restart without funding replay, invalid assignment/construct preemption, N80 40-tick replan only, obligation weight 1.30 + 0.50 + 0.5×loyalty, release on accepted replacement/failure, issuer-funded error distinction, rest-timeout drift intent, N148 idle-strike exclusive ownership, N146 actor-key command flush |

### Конкретный порядок соединения во второй фазе

1. Один world-snapshot per tick: positions, controller/relations, body Ice richness, unique real market buyer cash (ambiguity multi-market -> None), dock congestion, shipyard inventory (skip abandoned), location→system, contested body, payer balances; **никаких** экономических операций при чтении.
2. Для каждого проснувшегося N140 LOD корабля: N149 cargo/crew/fuel snapshot, N80 personality+replan policy; N135 assigned order, N152 board Posted/held and N104 exact funded quotes, N83 trade route, N103 mining/liquidation, N91 construction offers.
3. N153 contract selector, GOAP request builders, N80 score, N153 source order/combo/held recovery; **один** N81 planner ищет реальную цепочку; при no-plan однотактовый Idle. Нельзя запускать сгенерированные описания `plan_request` как команды — это входные данные GOAP.
4. N153 expands only actual N81 operator results, N84 runs one BT step; N88/N90 emit transaction-intents, N146 sorts command buffer by **actor entity bits**, N97/N104/N108 authorized Apply. Accepted/Paid/credits/cargo/XP/escrow сохраняются лишь по подтверждённым receipt, в одной реальной симуляции.
5. N148 applies idle/retirement strike cadence **один раз**; N149 consumes Crew Food/Wages **один раз**. No duplicating N72/N138/N16 or refund/release on a speculative Accept.

### Важные границы достоверности

- **Это code-only перенос, не интеграция.** `plan_request` — чистая модель вызова уже перенесённого N81; структура `LocMap` должна быть адаптирована в фазе 2. Получение payer quote/acceptance, external commerce, market-priority, GOAP action output и raw command receipts — недоверенные до реальной сборки. `CODE_UNVERIFIED`: Godot parser, headless, end-to-end, Rust/GDScript differential replay **не запускались**.
- `Native Rust` использует `f32`, `u64` и saturating-`i64` (включая overflows), отдельные HashMap с неопределённым iteration tie order. GDScript `float`/signed `int`, явно подписанные округления и source-order snapshots требуют дифференциальных пограничных тестов на фазе 2; не делать утверждение о byte-for-byte parity.
- При составлении максимума `plan_goal` код Rust `Iterator::max_by` отдаёт **последний** равный элемент; комментарий в Rust утверждает «earliest-pushed». N153 следует фактическому `max_by`, конфликт отражён здесь.
- Исходный `route_actions` при отсутствии пути даёт прямой `Travel` (не телепортацию); N153 сохраняет это только как намерение, реальное расстояние и топливо проверяет N59/N90.
- Все четыре `.gd` файла имеют чистые data/snapshot APIs без изменения мира. Подготовлено 17 source-derived fixtures в `n153_native_ship_ai_checks.gd`, **созданы, не исполнялись**. Статическая проверка всех 4 файлов: баланс скобок/кавычек, обнаружены все локальные preload ссылки, без парсера Godot.

## Решение по макро №4

**Исходная функциональная карта `ai/*` + `agents/ship/behavior.rs` + `agents/ship/actions.rs` по компонентным PR покрыта; по исходникам — SOURCE-COVERED в смысле фазы 1.** Это *не* работающий автономный ИИ в игре: без фазового единого World snapshot, N81/N84 и транзакционной Apply нельзя требовать поведения или исполнения. Если обнаружится отсутствующая native ветвь или несходство после Godot parser/Rust diff, вернуть макро в `SOURCE_GAP` и исправить конкретную функцию, не выдавать невыполненный runtime за done.

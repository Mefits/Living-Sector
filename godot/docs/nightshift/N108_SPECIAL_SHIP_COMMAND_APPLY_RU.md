# N108 — применение специальных команд кораблей из Rust

**Дата:** 12.11.2026. **Фаза 1 (покомпонентный перенос), статус:** `CODE_UNVERIFIED`. Исходная замороженная Rust Galaxy 0.6.7 — `archive/rust-galaxy-067-reference` SHA `6e40615be95cc6ddbabe21c3b94def5c52f8622d`. **Резервация:** `feature/godot-nightshift-20261112/godot/docs/nightshift/claims/N108.json`, создана атомарно ДО кода SHA `9490593e7109e0eed949396a393ef823ef386b6a`. Ветка `feature/godot-n108-special-ship-command-apply-20261112`, база `integration/godot-47-n33-n37-20261112`. N39/N100/другие исполнители, P1, `main` и frozen Rust не изменены. Godot не запускался согласно утверждённой стратегии.

## Замороженные первоисточники

- `native/crates/sim_server/src/engine/apply.rs`: SimCommand::RequestGateJump, SimCommand::RequestRefit, SimCommand::ReleaseContract, `apply_gate_jump`, а также порядок получения команд. Старый BT gate optimistically меняет позицию ДО exclusive Apply (источник сам помечает как риск рассинхронизации).
- `native/crates/sim_server/src/engine/admin.rs`: `try_shipyard_refit`, `apply_fitting_swap`, `commit_shipyard_refit`, `admin_refit_ship`. В отличие от агента, администратор через shipyard не тратит retrofit point; а admin override без верфи и денег меняет fitting.
- `native/crates/sim_core/src/modules/mod.rs`: 15 модулей (5 слотов × T1–T3), исходные множители скорости, трюма, топлива, дальность сенсоров, бонус связи, power_use / power_cap. `economy/module_production.rs`: 10 действительно производимых T2/T3 модулей и их исходные цены. `simulation/config.rs`: исходный базовый cargo/speed для 6 классов.
- `native/crates/sim_core/src/agents/facility/components.rs`: GateLink `fee_flat + fee_per_cargo_unit × cargo_used`; ModuleStock::take_one; исходный Hash/angle `facility_offset_position(body_center, facility_id)`.
- `native/crates/sim_core/src/economy/contracts.rs::ContractBoard::release`: Accepted→Posted с защитой от чужого ship, escrow сохраняется, agreed_payment сбрасывается, фиксированный faction strategy reward возвращается к `initial_payment`.
- `native/crates/sim_core/src/agents/faction_relations.rs`: `BREACH_STANDING_PENALTY=-1`, состояние пары ограничено [-100,100], default создаётся с tick. Бонусы/штрафы к репутации за нарушения — из exclusive ReleaseContract Apply.

## Перенесённые компоненты

1. `godot/scripts/port/n108_gate_jump_apply.gd`: **физически подтверждённый переход через настоящую пару ворот**. Источник `facilities_at_location[source]` задаёт первоначальный ordered выбор GateLink; cargo_used из реального груза; fee и платёж ship→original gate facility; position/docked_at и `ShipMemory.recent_systems` (5 последних систем). Координаты не выводятся из route weight, пикселей или новых генераторов: входной authoritative `facility.position` должен быть получен исходным `facility_offset_position`.
2. `n108_shipyard_module_catalog.gd`: соответствие 15 исходных модулей/10 цен и базовых 6 классов. Refit rollup по Rust `combine_effects`: множители перемножаются, дальность и бонусы складываются, power saturates u16. `power_ok` только отображается, оригинальный Rust **не** запрещает refit за превышение power budget.
3. `n108_shipyard_refit_apply.gd`: `agent_refit` проверяет docked-at real shipyard, наличие ModuleStock, достаточные credits и **один** retrofit point; atomically заменяет slot, пересчитывает cargo capacity и speed modifier, дебетует ship, кредитует FacilityOperations, расходует ONE stock и ONE point, публикует событие. `admin_shipyard` использует те же реальные товар/оплату, но в Rust не тратит point. `admin_override` разрешает пустой слот и прямую замену без верфи/денег — **только** для авторизованной административной точки входа.
4. `n108_contract_breach_apply.gd`: правильный fulfiller — единственный, кто может Release Accepted→Posted; никакого повторного возврата escrow, `agreed_payment=null`. При `reason == issuer_funding_failure` штраф НЕ применяется. Иначе потеря репутации `clamp(10+payment/1000, 1,25)`; если стороны в разных фракциях — standing -1, событие. Ship.active_contract_id остается до очистки BT (как в оригинальном ContractBoard release).
5. `n108_ship_special_apply.gd`: самостоятельный pure dispatcher разных `SimCommand` семей, возвращающий `{ok,world,events}` с detached `world` только после успеха. Выполнение admin-функций требует внешнего подтверждения прав (поле `authenticated_admin` показано как контракт, но **само по себе поле клиента НЕ является аутентификацией** — Phase 2 должен допускать это только из доверенного backend admin flow).

## Границы паритета и известные сознательные отклонения

**Оптимистический GateJump:** исходный Rust `actions.rs` перемещает локальную ShipPosition ещё до `apply_gate_jump`, а Apply может списать fee даже если связанный GateLink/орбитальная позиция назначения не разрешилась. В N108 эти случаи **fail-closed** до любого денежного/позиционного изменения; не утверждать буквальную идентичность этих ошибочных крайних сценариев. Это сохраняет источник правил перехода и убирает риск необеспеченного телепорта при интеграции. Реальный порядок фаз/стоимость/двойные команды и source coordinate hash должны быть проверены одним общим Godot-тестом **на фазе 2**, не раньше.

**Каталог дублирует неизменяемые числа N51** ровно потому, что эти PR пока независимы. Phase 2: использовать **ОДНУ** каноническую таблицу (N51/N108) и один общий `ShipFitting`/ModuleStock источник. Пересчёт fitting в source допускает cargo capacity ниже уже загруженного количества и power budget превышения; N108 не добавляет нового скрытого фильтра.

**Ledger и Clock:** новые source-derived функции получают полный авторитетный world snapshot, возвращают новую копию и событие. Они НЕ подключены к N11 денежному реестру, N39 production, N90 BT actions, N97 physical trade, N104 ContractBoard или P1. При Phase 2 `RequestGateJump`/Refit и ReleaseContract должны проходить **одну** глобальную Apply-фазу с проверкой idempotency, не через два независимых реестра/кошелька. `n108_contract_breach_apply` нельзя вызывать вместе с `n104_contract_funding.gd::release` для одной команды: это **один** переход + штраф, иначе дублирование. Refund escrow после Paid/Expired принадлежит N104, а не N108.

**Уточнения точности:** большие i64 и source f32-multiplier при граничном округлении требуют runtime-проверки только при Phase 2. Rust `DefaultHasher` для координат `facility_offset_position` не заменён самодельным числом; входная орбитальная позиция должна быть действительно рассчитана из Rust-паритетного источника. Умолчание по координатам запрещено, чтобы не рисовать/не телепортировать в выдуманное место.

## Контракт передачи на Phase 2

Состояние:
- `ships`: каждый stable Rust ID, текущая physical location/dock/credits/ship cargo, fitting slots+derived, cargo_capacity/speed_modifier, progression, reputation;
- `facilities` + ordered `facilities_at_location`: canonical gate_link и настоящий paired facility position (из body orbit+hash), ModuleStock, credits, facility_type;
- `contracts` + `relation_standing`: настоящий state/fulfiller, статус+reserved escrow и standing по канонической паре faction IDs.

**Дешёвая проверка на фазе 1:** наличие файлов и всех preload, баланс скобок, исходные константы и формулы в документации. Без Godot runtime/smoke/Windows ZIP. `CODE_UNVERIFIED` до сборки **ВСЕХ** механик в единый Godot (Фаза 2); улучшения Grok (Фаза 3) — потом.

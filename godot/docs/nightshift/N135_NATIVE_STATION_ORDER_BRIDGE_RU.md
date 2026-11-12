# N135 — перенос station orders и диспетчеризации кораблей, Phase 1

**Статус:** `CODE_UNVERIFIED`. Исходник заморожен: `archive/rust-galaxy-067-reference@6e40615`, `native/crates/sim_core/src/strategy/orders.rs` (380 строк без `orders/tests.rs`, ~23 KB), плюс оригинальные тесты `strategy/orders/tests.rs` (269 строк). Исходник — единственный источник механик. Это не интеграция в работающий Godot P1.

## Границы компонента

- `godot/scripts/sim/n135_station_orders_core.gd`: `Order::new/assign/release`, `may_accept`, `assigned_contract`, `builder_assigned`, фиксированный проектный платёж и `funding_top_up`, отбор/приоритет контрактов, неизменяющий экономику `snapshot`.
- `godot/scripts/sim/n135_station_orders_dispatch.gd`: полный диспетчер `dispatch`, этапы maintenance существующих заказов, выбор судна, особая защита станции с T1-сенсорами, смена источника у ещё не принятого и оплаченного фракционного заказа, занятость грузовых судов/строителей, выдача подтверждённых рыночных цен пилотам как **отдельных намерений**.
- `godot/scripts/sim/n135_station_orders_checks.gd`: небольшой сценарий, отражающий оригинальные Rust инварианты; во время фазы 1 Godot не запускается.

## Входные данные и владение состоянием

Вызов `Dispatch.run(snapshot: Dictionary)` — чистая функция от единого снимка; возвращает `{contracts, sites, price_quotes, error, staged}`. Если `executing=false` (Shadow), возвращает исходные копии. Только внешняя транзакция будущей **Фазы 2** может принять полученные staged changes; сам диспетчер не подтверждает, не оплачивает и не доставляет ни один контракт.

Обязательный снимок:

```text
{
  executing: bool, tick: int, multiplier: int, galaxy: bool,
  contracts: Array[Contract], sites: Array[ConstructionSite], ships: Array[Carrier],
  markets: Dictionary[location -> {supply:{commodity:float}, prices:{commodity:float}}],
  owners: Dictionary[location -> faction_id],
  relations: Dictionary[faction_id -> Dictionary[faction_id -> treaty_name]],
  facility_payers: Dictionary[facility_id -> credits:int],
  locations: Dictionary[location -> {system:system_id, body_id:id}],
  orbits: Dictionary[body_id -> {orbit_radius:float, orbit_period:int}],
  distances: Dictionary[from_location -> Dictionary[to_location -> shortest_distance:int]]
}
```

Только авторитетная `WorldRegistry.shortest_distance` заполняет distances — **запрещено** подменять его евклидовым расстоянием. `locations` / `orbits` получаются из `WorldRegistry` и `BodyOrbit`; для экспедиции требуется фактический `can_rendezvous`. `galaxy` означает наличие `Director` (в Rust это не космическая география), а не произвольный игровой флаг. `relations` должны быть отражены в оба направления с тем же treaty, что и `FactionRelations.state_or_default`; отсутствие записи = Neutral.

Для каждого `Carrier`: `id, faction, class, location, credits, fuel_fraction, speed, in_transit, active_contract_id, transaction_pending, reputation, sensors, comms_bonus, cargo_used`, а также `cargo_free` либо `cargo_capacity`. Эти значения берутся из `ShipIdentity/Position/Transit/Cargo/Economy/Fuel/Fitting`; неполный корабль не назначается. `passenger_capacity` — только из `simulation::config::ship_class`; `crew_roles` — только из config для строителей. Нельзя считать отсутствующие транзакции/транзит автоматически пустыми. Статус и типы контрактов — Rust variant `Posted, Accepted, PickedUp, Delivered, Paid, Expired` и `Delivery, Passenger, Construction`. Товары используют сериализованные `snake_case` Rust `Commodity` (`food, water, ore, ...`).

`Contract` включает `id, status, contract_type, faction_id, requestor_id, fulfiller_id, source_location, destination_location, commodity, quantity, payment, initial_payment, posted_at_tick, mission_category, min_reputation, funding`. `funding` содержит `source` (`Faction`/`Facility`), `reserved` и `station_order` (Dictionary или null). `Order` использует `executor_id=""` и `blocked_reason=""` как локальные пустые Option — **при сериализации в оригинальный Rust формат** адаптер обязан конвертировать их обратно в `null`. Не считать пустую строку настоящим идентификатором.

`ConstructionSite`: `id, faction_id, location_name, completed, dirty, remaining` (реальный `progress_required-progress_delivered`) и `labor` с `required, completed, station_order, last_shift_tick, last_executor, blocked_reason, colony_source`. Отсутствующее `remaining` трактуется как ещё не доставленные материалы, никогда как бесплатная готовность стройки.

## Семантика Rust

1. Единственное назначение на контракт: приоритет `food/water` → пассажиры → остальные, затем `id` по алфавиту; судна выбираются с приоритетом `fuel >= 0.25`, затем минимум суммарных шагов, затем `id`. Принятые заказы имеют приоритет над новыми, участники строительства делят общий used-set.
2. Обновление состояния без фиктивных ресурсов: `attempt` ограничен u32, `cooldown=30*mult`, `lease=300*mult`; отдельная проверка отсутствующего корабля, занятого судна, истёкшего lease. `Paid`/ `Expired` лишь отмечают существующий факт, не платят/возвращают эскроу.
3. Station Facility Delivery забирается диспетчером только через 180 тиков без исполнителя либо при прежнем station_order. Даже при незанятости **T1 сенсоры не разрешают межсистемное назначение**. Нужны существующий `reserved > 0`, достаточный `facility_payers` для допустимого top-up и реальный рынок.
4. Faction strategy — исключительно существующий `fixed_strategy_reward` с полным `funding.reserved`. Закупка допустима только по действительной `market_buy_multiplier` (отношения, репутация) и реальным цене, складу и кредитам корабля. Если источник недоступен, разрешён fallback на другую локацию **только для Posted фракционного контракта**, сортировка: свой рынок → маршрут → цена → source → ship. Источник меняется, но ни склад, ни деньги не меняются.
5. После выбора сформировать `price_quotes` (источник, товар, price, tick) для будущего применения в `ShipMemory.price_knowledge`. Не увеличивать спрос/склад, не снимать эскроу и не принимать контракт при публикации котировки.

## Смежные PR / Фаза 2

Не заменяет N90 действия кораблей, N97 физический `engine/transactions.rs`, N104 ContractBoard/escrow, N79/N119 верфи, N108 special Apply, N134 Head decision и N39 production. Реальный порядок: один authoritative world/board snapshot → N135 stage → exclusive validated commit → фактическое принятие судном через native `may_accept` и физические транзакции. Вызов повторно с тем же состоянием не должен дублировать кредит/груз; snapshot order assignment и 64-bit tick сохраняются через интеграционный save adapter.

**Непроверенные тонкости:** точность Rust f32→f64 в цене закупки и round/ceil на критических границах; путь сериализации Rust Option и конкретные структуры сериализованного ContractBoard; live ShipFitting и полное совместное World+Board tick. Короткая проверка структуры скриптов — не Godot parser/runtime, поэтому остаётся `CODE_UNVERIFIED`. Полная стыковка в Фазе 2, улучшения Grok в Фазе 3.

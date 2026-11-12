# N147 — полноценная миграция рабочей силы в колонию: source-port, не игровая интеграция

**Источник:** frozen Rust Galaxy 0.6.7 `archive/rust-galaxy-067-reference`, `native/crates/sim_core/src/strategy/colony_development.rs::migration_proposals` и `::commission` (примерно строки 239–329), связанные оригинальные `economy/contracts.rs::post_passenger_for/register_prepaid`, `agents/faction.rs::FACTION_SUBSIDY_FLOOR=5000`, `CONSTRUCTION_LIFESPAN_BASE=800`, `agents/population.rs::PASSENGER_PAYMENT_PER_HEAD=80`, `colony.rs::SETTLERS=10`, `world/registry.rs::shortest_distance`. N147/claim создан атомарно на общей ветке до реализации (commit `5c80a107`). **Макро №2, Phase 1.**

## Проверка пересечений

- **N92, PR #180:** `observe`, `next_supply_goal`, часть `migration_intent` — только мониторинг и намерение. Его собственный документ явно сообщает, что оплаченный `commission()` НЕ перенесён. N147 не переписывает обзор N92, а принимает его `ColonyView`.
- **N114, PR #203:** совсем другая функция `agents/population.rs::run_population_migration` — демографический отток из недовольных мест. N147 переносит **продуманный оплаченный пассажирский контракт**, без прямого перемещения людей.
- **N118, PR #207** и **N144, PR #232:** первичное основание колонии, не последующая нехватка рабочей силы.
- **N126, PR #214:** пассажирские предложения от самих домохозяйств; N147 — отдельный запрос **фракции** с её казённым авансом.
- **N16 / N104** — контрактная книга, оплаченная резервация/возвраты; **N97** — реальные корабельные транзакции и доставка. Им принадлежат фактические проводки; N147 делает только проверенный *intent*, не вторую книгу денег.
- **N142, PR #231:** `WorldRegistry::shortest_distance` по реальным физическим directed corridors, не N59, включающий дешёвые врата. Поэтому маршрут до источника переселенцев всегда относится к доступным физическим переходам.

## Новый исходный перенос

1. `godot/scripts/sim/phase1/n147_native_colony_migration_planner.gd`: полный source-backed `migration_proposals(world, board, views)` по фактам реальных N92-колоний:
   - Colony `phase=migration`, `missing_workers>0`, `market_unambiguous`, нет активного passenger contract; food/water запасы **не ниже** реальных forecast reserves;
   - переселенцы `clamp((missing_workers * 5 + 2)/3, 1, 20)`, стоимость `quantity×80` CR, резерв казны `5000`;
   - другая станция **той же фракции** с реальным физическим путём до колонии и живым домохозяйством минимум `quantity+10` жителей;
   - корабль **той же фракции**, с реально подходящей `ship_class.passenger_capacity`, fuel>0, не в пути, не занят личным контрактом, не закреплён `fulfiller_id` у другого outstanding контракта; местоположение в источнике либо физически достижимо;
   - сортировка станций-источников и one-plan-per-faction из Rust `BTreeMap`; входные `ColonyView` отсортированы точно как Rust `observe` (faction, location). Нет генерации колонистов или нового транспорта.
2. `godot/scripts/sim/phase1/n147_native_colony_migration_commission.gd`: полное независимое вторичное preflight `commission()` перед настоящей оплатой:
   - запрет второй заявки passenger **того же requestor/faction+destination** пока в книге есть outstanding, включая expired/paid с непустым не возвращённым `funding.reserved`;
   - реальные исходное и приёмное домохозяйства (recipient обязателен: доставка НЕ создаёт новый pop entity);
   - физический directed маршрут source→destination и свободный существующий корабль подходящей вместимости, возможный марш до source, fuel>0; **source's commission не проверяет board's external fulfiller assignment** — это отличие от предварительного planner, сохранено по оригиналу;
   - реальная казна фракции оставляет минимум 5000 CR после аванса `quantity×80` (точная граница допустима);
   - intent **ровно одного** `ContractBoard.post_passenger_for(requestor=faction, faction_id=Some(faction), quantity, source, destination, payment, tick, 800×tick_multiplier)`, далее `register_prepaid(source=Faction,reserved=payment)` и дебет **казны фракции** на payment. Внутренний ContractType Passenger в оригинале хранит `Commodity::Food` как placeholder, **прибытие изменяет households, не Food-stock**;
   - оригинальный mission-category `strategy.colony.workforce.v1` и событие `colony_workforce_contract_posted` возникают только после настоящего подтверждённого постинга;
   - метод `verify_native_commission_receipt` лишь сверяет настоящий внутренний, уже совершённый board+treasury receipt — **не принимает сетевой/UI словарь как доказательство проводки**. Контрактный ID выдаёт сам authoritative `ContractBoard`, а не генератор N147.
3. `godot/scripts/sim/phase1/n147_native_colony_workforce_checks.gd`: source-derived сценарии: успешная колония, 10 переселенцев/800 CR, исходные 800×mult, устойчивый source, реальная задолженность, запрещённый дубликат, expired-but-not-refunded, lack of ship/fuel/route/recipient/settlers/treasury, cash conservation, forged escrow receipt. **Написаны, но НЕ запускались.**

## Входной интерфейс Фазы 2

`Planner.plan(n92_views, native_world_projection)`: `native_world_projection` — исключительно **read-only** snapshot, валидированный из оригинального ECS:
```text
{
 treasuries: {faction_id: int},
 stations: [{faction_id, facility_type: "station", location}],
 households: [{faction_id, location, population_count: int}],
 ships: [{id, faction_id, class, has_native_cargo: true,
          location: string|null, active_contract_id: string|null,
          in_transit: bool, fuel: float}],
 ship_classes: {class_name: {passenger_capacity: int}},
 contracts: [{id, type:"passenger"|..., requestor_id, status,
             destination_location, fulfiller_id, reserved_credits}],
 physical_distances: {from_location: {to_location: int(u32)}}
}
```
`physical_distances` должен быть результатом **реальных N142 `shortest_distance` (physical only)**, не экранных координат и не маршрутизатора N59 с gate-teleport. Истинность `has_native_cargo` должна быть получена из реально присутствующего `ShipCargo`, а `active_contract_id` — от настоящего ShipEconomy.

`Commission.prepare_commission(world, faction, selected_plan, tick, multiplier)` вызывается только из настоящего native strategy dispatcher, с повторным текущим ECS/Board snapshot. Ответ — `{ok, post, treasury_delta, escrow_reserved, preconditions,...}`, **не оплата**. Реальный owner должен:
1. заново проверить post и preconditions against world+board, удержать сумму у исходной фракции, создать новый Passenger contract, привязать advance FundingSource::Faction/reserved, выставить `mission_category`;
2. **в одной атомарной транзакции** записать казну, ContractBoard и native save cursor. При ошибке ничего не применять (нет сиротского escrow или бесплатного контракта);
3. только после этого передать `trusted_internal_apply` и реальный `contract_id` через внутренний механизм, вызвать `verify_native_commission_receipt` для source-consistent события.

Нельзя применять результат N147 прямо через UI и нельзя одновременно вызывать два разных `register_prepaid` (N104 + N147). Погрузка пассажиров, перевозка, высадка, возвраты/истечение, reputation — другие *уже перенесённые* native modules, не добавлять мгновенный прирост населения.

## Границы и честный статус

Для `migration_proposals` и `commission` **исходное GDScript покрытие готово**; это один закрытый N147, но **макро №2 целиком ещё НЕ закрыт**. Остаются исходные ветви `population.rs` и другие колониальные действия на аудит. Статус `CODE_UNVERIFIED`: только GitHub file readback и статические скобки/кавычки, без Godot parser/headless и без реального Rust/Godot parity replay. Объединение PR — отдельная **Фаза 2**. Данные не подменяют авторитетные ECS или ContractBoard и не доказывают игровую работоспособность.

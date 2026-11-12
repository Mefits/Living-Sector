# N104 — исходное контрактное финансирование, escrow и доставка

**Фаза:** 1 — перенос уже существующей Rust Galaxy 0.6.7. **Статус:** `CODE_UNVERIFIED`; Godot не запускался по решению пользователя. **Ветка:** `feature/godot-n104-contract-funding-escrow-20261112`, от `integration/godot-47-n33-n37-20261112`. Резервация N104 атомарно создана до кода в `godot/docs/nightshift/claims/N104.json` (coord branch), SHA `e86e94c9f6875b5c7ee22380e0435c994f42740d`. N39 production и N100 hybrid других исполнителей не менялись. P1, main, frozen Rust не затронуты.

## Первоисточники в frozen Rust

- `native/crates/sim_server/src/engine/contract_funding.rs`: `quote`, `account`, `set_balance`, `accept`, `refund_closed`. **Один реальный плательщик**: Population.total_wealth, FacilityOperations.credits или FactionData.treasury. Никогда не финансировать заказ за счёт другого рынка.
- `native/crates/sim_core/src/economy/contracts.rs`: `ContractFunding` (source, reserved, agreed_payment, station_order, embarked), `acceptance_payment`, `fixed_strategy_reward`, `funding_top_up`, `ContractBoard::{accept,release,mark_picked_up,mark_delivered}`. Старые контракты без `funding` НЕ считаются оплаченными.
- `native/crates/sim_core/src/strategy/orders.rs`: `may_accept`, `assigned_contract`, `builder_assigned`. Стратегические очереди и строительные назначения не обходятся обычным кораблём.
- `native/crates/sim_core/src/agents/faction_relations.rs`: `trade_pact_payment_multiplier` (1.10/1.15) и коммерческий запрет для Hostile/War. Базовая котировка учитывает comms_bonus (в source из ShipFitting.derived). **Фиксированная награда** faction-проектов `strategy.logistics.v1`, `strategy.construction.v1`, `strategy.colony.v1` берётся только из `initial_payment`: дополнительные списания без полномочия запрещены.
- `native/crates/sim_server/src/engine/transactions.rs` `embark`, `deliver` и `engine/apply.rs::commit_contract_delivery`: физические груз, пассажиры и имущество, последующий escrow payout, репутация, опыт, разные типы получателей. Пассажирский лимит — оригинальная `simulation/config.rs`, защита десяти `strategy/colony.rs::SETTLERS`, household food satisfaction `FOOD_SAT_RECOVER_ON_MET=2`.

## Четыре независимых GDScript-компонента (~900 строк)

1. **`scripts/port/n104_contract_quote.gd`**: `fixed_reward`, `quote`, `top_up`, `may_accept`, treaty/commerce. Сохранены original 7 contract kinds и 3 escrow funding sources. `Option<faction_id>::None` не превращается в фиктивную фракцию; source-deterministic order gates.

2. **`scripts/port/n104_contract_funding.gd`**:
   - `accept(world, ship, contract, tick)`: исключительно Posted→Accepted, предварительная проверка ship, builder/assigned orders, treaty, другого active contract, evidence escrow, согласованной суммы и реального текущего баланса плательщика. Списать **только разницу** `max(agreed-reserved,0)`; записать `reserved`, `agreed_payment`, ship.active_contract_id и событие лишь в целиком новом world snapshot.
   - `release`: при правильном исполнителе Accepted→Posted, без второго дебета, escrow остаётся зарезервированным; `agreed_payment=null`, стратегический `payment` возвращается к фиксированной исходной сумме. Штраф за нарушение контракта — **отдельная** source-логика `engine/apply.rs::ReleaseContract`, не выдумывается при локальном release.
   - `refund_closed`: после Paid/Expired сортирует заявки по ID, возвращает **весь оставшийся escrow** точно исходному плательщику, затем обнуляет reserved. Если аккаунт пропал или сумма переполняется, не создаёт нового получателя, оставляет резерв для восстановления.

3. **`scripts/port/n104_passenger_contracts.gd`**:
   - `embark`: только accepted funded Passenger, назначенный ship, точный реальный док и разрешённый owner; source passenger capacity по классам (colonizer 50, courier 20, freighter 10, hauler 5, tanker/miner 0), запрет повторной посадки, защита оставшихся 10 поселенцев для colony-проекта.
   - Поиск населения с подходящей faction/location и достаточным count+wealth, **лексикографически первый household ID** по Rust `min_by_key`. Из population_count и total_wealth реально вычитаются пассажиры и доля денег, сохраняется манифест `funding.embarked`, Accepted→PickedUp. Никакой «появившейся» популяции на маршруте.

4. **`scripts/port/n104_contract_delivery.gd`**:
   - `deliver`: источник ship.active_contract_id, правильный fulfiller, Accepted/PickedUp, допустимая commerce, реальные agreed_payment и escrow >= agreed, нет переполнения ShipEconomy. Обязательная проверка дока/контроллера на destination. Платёж **escrow→корабль**; `status=paid`, `funding.reserved -= payment`, `active_contract_id=null`, манифест очищается. Любая ошибка — исходный world неизменен.
   - Passenger: только после Embark, реальные recipient population+wealth пополняются на destination, проверка overflow/ownership. Household Delivery: купленный из escrow `food` потребляется именно домохозяйством, не попадает вторично на рынок. Construction Delivery: ресурсы из трюма физически переходят в matching site.progress_delivered (не в рынок); завершение стройки остаётся делом отдельного Rust/N91 construction-компонента. Обычные Delivery/Courier/Supply/Subsidy перемещают подтверждённый груз из hold в supply рынка действительной facility.
   - Сопутствующие последствия `commit_contract_delivery`: заплатить один раз, прирост личной репутации `clamp(5+payment/2000,1,15)`, двустороннего standing +2, убрать hoard strikes, `personality.profit += 0.002`, прогресс корабля +15 XP (level cap10 и retrofit points) и crew trading/navigation +1. CrewMission skill gain по восьми native `missions.rs` категориям. Данные, которых нет как компонента в Rust, не создаются наугад.
   - `Paid` с излишне зарезервированными средствами обрабатывается отдельным `refund_closed`, иначе сумма была бы завышена.

## Контракт интерфейса на Фазу 2

Текущие data-only функции **получают целиком авторитетный snapshot** `world` и возвращают новую копию плюс события; они НЕ мутируют P1, N11 ledger, N39 производство или user:// файлы.

Минимально необходимые слоты:
- `ships`, `contracts`, `populations`, `facilities`, `factions`, `construction_sites` — конкретные Rust identities, escrow и физическая собственность;
- `relations`: симметричные пары treaty, `relation_standing`: настоящие стояния/времена, `market_controllers`: owner по месту;
- `markets`: market.source facility ownership, physical supply; без фантомных markets;
- ship/dock/crew/progression и population.sentiment при наличии исходного ECS-компонента.

**Интеграционный долг, не делать до конца фазы 1:** `ContractBoard` держит status/destination/faction индексы; при публикации снапшота интеграционная фаза должна одновременно обновить эти индексы и глобальный N11 ledger. Операции N104 и N97 должны исполняться в одной exclusive Apply, иначе можно потерять согласованность escrow при двух клиентах. Статус никакой из подсистем не равен «готовому Godot gameplay».

## Ограничения и границы точности

- Rust использует `f32` comms/treaty и `f64` округление выплаты. GDScript double на крайних числах может дать пограничный другой бит; quote для денег выше 2^53-1 отказывает вместо ложного округления. Пассажирский Rust i128 wealth prorating тоже требует отдельного i128-адаптера для больших чисел; ниже 2^53 перенесён точный int/div.
- Схемы дублированных, старых или неконсистентных snapshot, индексная структурная валидность и фаза persistence проверяются только при общей сборке Godot (Фаза 2). Нельзя называть N104 runtime-VERIFIED, сборкой игры или выполнением всех legacy миграций.
- `apply.rs` fallback грузов стройки, компенсации за нарушение договора, `drains` materialization/Save, общие рынок/деньги/закупки и фракционные treaty-требования в других кодовых блоках и должны быть сведены один раз в Phase 2.

**Дешёвая проверка в этом PR:** 4 исходника + исходные Rust-fns сверены, все preload paths существуют, баланс круглых/квадратных/фигурных скобок по 0, длинные условия разбиты. Godot не запускался. **Следующий этап:** сначала закончить все Rust-механики; потом единая сборка; потом отдельные правки от Grok.

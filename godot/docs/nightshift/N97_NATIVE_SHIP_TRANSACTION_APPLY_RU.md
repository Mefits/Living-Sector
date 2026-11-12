# N97 — исключительная Apply-фаза физических ShipTransaction (Rust → GDScript)

**Дата:** 12.11.2026. **Статус:** CODE_UNVERIFIED. Первый этап — только покомпонентный перенос; не собирать проект и не запускать Godot до фазы 2. Предыдущий N90 [PR #182](https://github.com/Mefits/Living-Sector/pull/182) только создаёт ShipAction экономические запросы; **N97 применяет физические последствия на снимке состояния**. Проверенная P1 и N39 production не изменены.

**Резервация:** `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N97.json`, создана первой записью (commit `d802056136f5aa161ff496eed2205a69b49918a9`). Ветку N94–N96 параллельный разработчик уже забронировал, N97 назначен без перекрытия.

## Авторитетные источники Rust Galaxy 0.6.7

- `native/crates/sim_server/src/engine/transactions.rs`: **apply_transaction**, `buy`, `sell`, `affordable_sale_quantity`, `mine`, `refuel`, `dock`, `controller`, `market_at` и точные ошибки допустимости. Реальная exclusive Apply использует mutable World и не интерливит другие команды в середине проверки.
- `native/crates/sim_core/src/agents/ship/transactions.rs`: `ShipTransaction`, transient `TransactionSlot` с `pending.id` / `pending.result`.
- `native/crates/sim_core/src/economy/commodities.rs` и `agents/market.rs`: 17 товарных категорий, fallback базовых цен, рынок привязан к реально существующей facility, `MarketPricing::price`.
- `native/crates/sim_core/src/agents/faction_relations.rs`: `commerce_allowed` + `market_buy_multiplier`, используемый на **обеих** сторонах сделки. Market `sell_multiplier`/reciprocal здесь не использовать.
- `native/crates/sim_core/src/agents/facility/components.rs`: `REFUEL_UNITS_PER_TICK=2.0`, `REFUEL_PRICE_PER_UNIT=2`; `agents/facility/mod.rs`: `SALVAGE_UNITS_PER_RICHNESS=8000`; `agents/ship/components.rs`: `RouteStats` содержит `attempts`, `total_profit_per_unit`.

## Что перенесено

1. `godot/scripts/port/n97_ship_market_rules.gd`: таблица 17 базовых цен; тариф по репутации, контроллеру и treaty, допуск коммерции, цены и запасы фактического market. Для собственных фракций эффективная репутация 100, для свободных рынков 50; Hostile/War закрывают торги и увеличивают **положительную** наценку, когда применяется в расчёте цен. Отсутствующий source relation = Rust default neutral, но неверные договоры и противоречивые направления отвергаются.
2. `godot/scripts/port/n97_ship_physical_settlement.gd` — `simulate(world,ship_id,request,tick)`: **полная автономная копия world**, вся проверка перед выдачей. Выдаёт изменённый снимок только на успешной операции; исходный не модифицирует. Никакого редактирования P1 и `user://`.
   - `Buy`: реальная док-станция, controller и рынок, treaty/embargo, quoted × posture, изменение цены выше `max_unit_price` отменяет сделку, `quantity<=2^24`, реальный market stock / free hold, `ceil(price×qty)` зачисляется именно оператору рынка, у корабля списывается, весь товар загружается в трюм с source age и unit_cost.
   - `Sell`: аналогичная проверка; **платит только фактический market operator** из собственного баланса. Количество может быть уменьшено до платёжеспособного объёма бинарным поиском `floor(price×qty)`. Реальный market supply увеличивается, груз уменьшается, cargo origin/age удаляются только при полной продаже; фиксируются успешные route stats и trade volume.
   - `Mine`: только корабль класса miner, только `ice`, тело в той же системе, точное `mine-<body_id>`, физический ход не занят, `quantity<=40`; остаток body richness уменьшается на `extracted / 8000`, добыча добавляется в трюм **без создания денег/market supply**, отмечается работа инженерии.
   - `Refuel`: реальный dock, сначала FacilityStorage.reserves[Fuel], затем market Fuel **только если этот рынок принадлежит доку**; не больше 2 единиц топлива на шаг и реального свободного бака. `ceil(transferred)×2` платится оператору дока, без генерации топливных запасов.
3. `godot/scripts/port/n97_ship_transaction_apply.gd` — exclusive `apply(world,ship_id,request_id,tick)` читает только один pending ShipTransaction; неверный/повторный/уже отвеченный ID — silent no-op по Rust, отсутствие допустимости — отрицательное подтверждение в **копии mailbox** без экономического изменения. При успехе публикуется изменённый мир плюс положительное подтверждение, общий source event `ship_transaction_applied/rejected` с quantity/payment/reason и dirty lifecycle.

### Как соединять в фазе 2

World snapshot должен предоставлять `ships`, `facilities`, `markets`, `bodies`, `relations`, `market_controllers`. Контракт структуры перечислен в начале `n97_ship_physical_settlement.gd`. ID dock-станции и ID ship должны совпадать с реальным авторитетным реестром. На Phase 2 **не создавать ещё один денежный реестр**: применять полученные дебет/кредит к единому N11 Ledger, а stock/reserves/body/cargo — в одном общем коммите; если любой домен не проходит, исходный мир оставить прежним. Между входным snapshot и публикацией результата требуется строгая эксклюзивная фаза без интерливинга.

**Пограничная точность:** Rust хранит цену и supply как f32, но денежные расчёты делает через f64. В GDScript double значения могут слегка отличаться на границе округления; этот data-only порт не объявлен verified по точному floating-point битовому поведению, и на Phase 2 нужен совместный тест цен и плейбэк. Для больших сумм, которые невозможно представить целым f64 без потери точности, расчёт fail-closed (до 2^53-1) — не выдавать ложную фразу «полный паритет денежных границ».

## Что остаётся в Rust и НЕ притворяется готовым в N97

- `engine/contract_funding.rs`: Accept с реальным escrow, плательщиком и подтверждением. `engine/transactions.rs` часть `embark/deliver`: реальные переселенцы/социальная экономика, обеспеченная escrow оплата, передача груза стройке, household delivery. **N97 возвращает deferred**, не отвергает подтверждённый контракт и не начисляет деньги без отдельного исходного переноса.
- `engine/apply.rs::apply_gate_jump` и `engine/admin.rs::commit_shipyard_refit`: настоящая цена шлюза/модернизации и применение изменений остались отдельными Rust-механиками. Планы N90 не являются доказательством их исполнения.
- Работа построек и N39 production по прежнему принадлежит другому исполнителю. Промежуточная тестовая сборка Godot и пять маленьких smoke-прогонов **не нужны**.

## Быстрая проверка без Godot

Статические GDScript-пути и source references, наличие целевых preload, баланс скобок, сверка перечисленных формул и критических ветвей. Код **не исполнялся** в Godot; `CODE_UNVERIFIED` сохраняется до объединения всей первой фазы и общей приёмки второй.

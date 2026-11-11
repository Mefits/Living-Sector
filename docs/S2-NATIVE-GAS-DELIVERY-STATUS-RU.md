# S2 — первый безопасный блок: реальные статусы газовых заказов

## Основание (только реальные данные)

- Чистый Windows Genesis 0.6.2 x16 после исправления сенсоров: workflow https://github.com/Mefits/Living-Sector/actions/runs/43011866774
- Повторный анализ тех же 15 снимков без нового игрового прогона: https://github.com/Mefits/Living-Sector/actions/runs/43018334495
- На тик 1806: Earth Station (terran-authority) gas=0, shortage_ticks=1790. Gas offers from alpha-station: contract-21/29/32/40/68, 200 gas each, no contract_delivered event to Earth.
- Huge Hauler Genesis является единственным судном с T2 sensors в этом начальном флоте. Он реально взял **contract-8**, metals x100 из Earth в Alpha (не газ), в тике 265 отправился и к тику 1806 был в полёте, с **100 metals физически на борту**. Native transit на последнем снимке: departure_tick=265, arrival_tick≈1970, from=earth-station, to=alpha-station. Следовательно, тест до 1806 тиков закончился ДО нормального ETA. Трактовать его как «зависшего» было бы ошибкой.
- Native code: normal market-delivery cargo acquired with ShipAction::Buy and still ContractStatus::Accepted while in flight. Native settlement explicitly permits Accepted→Paid directly (contracts.rs: mark_delivered); stage PickedUp обязателен лишь для иных сценариев (например, пассажиров).
- Normal physical delivery event contract_delivered writes after native market supply increment, с contract_id/commodity/destination, **но без quantity**. Quantity берётся только из того же нативного контракта; construction goes to construction site, household-funded food goes directly to population, не в рынок.

## Задача 1: не маскировать невыполненный заказ сообщением administrator_busy

В native/crates/sim_core/src/strategy.rs добавлено поле GoalAssessment.pending_delivery (только read-only, без нового хранилища):
- contract_id, source, quantity, status, posted_at_tick, age_ticks,
- fulfiller_id, station_order_executor_id, station_order_blocked_reason,
- reserved_credits.

Нативный GoalAssessment.reason теперь различает:
- existing_contract_unassigned — Posted, но нет ни accepted carrier, ни assigned station order;
- existing_contract_unassigned_stale — такой Posted без исполнителя существует >=180 игровых тиков;
- existing_contract — есть реальное назначение/принятие/исполнение;
- existing_contract_refund_pending — expired с ещё удержанным escrow.

Тест: после 60 тиков unassigned, после 360 — stale, после native Board.accept на том же contract_id — accepted. **Ни повторного контракта, ни новой траты, ни поддельного товара не появляется**. Варианты существующих других целей у Главы остаются доступны.

Порог 180 тиков — **только для диагностической метки**, не сетевой таймаут, не принудительное переназначение и не новая механика модулей.

**Проверка:** https://github.com/Mefits/Living-Sector/actions/runs/43018985344 (6 native strategy tests SUCCESS + cargo check -p sim_server SUCCESS).

## Задача 2: Golden не должен отвергать настоящие доставки по ошибочной схеме

В диагностической ветке PR #61 изменён ci/sol_s0/analyze.py:
- proof delivery теперь совпадение настоящего native contract_delivered event с contract_id, commodity, destination, contract_type и положительным native contract.quantity;
- для стандартных facility/faction market-delivery нужен наблюдённый положительный escrow; отсутствие event/quantity означает **не подтверждено**, Paid alone тоже не доказательство;
- construction site и household consumption намеренно не принимаются за пополнение рыночного склада;
- отсутствие PickedUp/Delivered в истории обычного груза не считается ошибкой сервера;
- relief_verified остается unknown — сам факт поступления партии ещё не означает устойчивого устранения дефицита.

**Проверка:** https://github.com/Mefits/Living-Sector/actions/runs/43019763288 (cached original real run + anti-false-green tests SUCCESS).

## Что ещё открыто — следующий маленький блок

1. Реально сопоставить нужную газовую поставку с available interstellar carrier: source route, cost/reward, занят ли Hauler контрактом metals до ETA≈1970, и почему глава довольствуется «existing_contract», хотя нет исполнителя.
2. Включить видимый stalled reason в решение главы/администратора и выбрать корректный штатный способ обеспечить выполнение (а не безлимитно создавать дубли, выдавать бесплатные ресурсы или игнорировать межзвёздный sensor gate).
3. Когда назначение/покупка подтверждены нативной транзакцией, провести короткий replay с достаточным горизонтом и проверить delivery_receipt + impact; затем Golden-v1 food/water.

**Нет доказанного gas relief**. Это самостоятельная экспериментальная ветка на основе PR #64. Stable/main, оригинальные SQLite, модули, планеты, UI, баланс неизменны.

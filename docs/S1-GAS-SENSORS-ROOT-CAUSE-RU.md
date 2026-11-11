# S1 — почему грузовик не видел газовые контракты Earth Station

**Статус:** точечный кодовый фикс выполнен; до завершения Windows runtime S1 нельзя объявлять реальную доставку и восстановление дефицита доказанными.

## Откуда факты

- Реальный Genesis 0.6.2 Windows на чистой SQLite, x16, 15 снимков до тика 1813, 3478 событий `/ws`: [исходный capture](https://github.com/Mefits/Living-Sector/actions/runs/43003469177), [перепроверка контрактов/флота](https://github.com/Mefits/Living-Sector/actions/runs/43010649065).
- Цель поставок: `earth-station` (Genesis Initiative, internal faction ID `terran-authority`); источник — `alpha-station` (другая звёздная система).
- На тике 1813 газ Earth = 0, shortage_ticks = 1798. Пять контрактов `contract-21`, `-29`, `-32`, `-40`, `-68` остались `posted` или `expired`; native pickup/delivered на Earth gas не подтверждены.
- На тике 1813 у фракции был свободный Huge Hauler, но реальный `/api/report.ships[]` показывал `fitting.modules.sensors=sensors_t1`, `fitting.stats.sensor_range_au=1.0`.

## Точная первопричина неверного fitting

1. В `native/priv/galaxy/data/worlds/sol.json` начальные корабли перечислены с *частичным* `fitting: {"comms":"comms_t2"}`: явного выбора `sensors` там нет.
2. В `native/crates/sim_db/src/spawner.rs` до фикса `ShipFitting::new_for_size(ShipSize::Huge, ...)` вызывался только для **полностью пустого** JSON `{}`. Если задан хотя бы `comms_t2`, `parse_ship_fitting` дополнял все отсутствующие слоты базовыми модулями T1.
3. В `native/crates/sim_core/src/agents/ship/components.rs` уже имелся правильный размерный стандарт: `ShipSize::Huge` должен по умолчанию получать `sensors_t2`.
4. В `native/crates/sim_core/src/agents/ship/behavior.rs` обычные контракты из другой системы отфильтровываются при `sensor_range_au < CROSS_SYSTEM_SENSOR_RANGE_AU` (порог `2.0`).
5. Наблюдавшиеся газовые контракты профинансированы `facility`, а не `faction`; поэтому механизм `strategy::orders` для отдельных оплаченных фракцией заданий их не назначает, и исключение для *назначенного faction strategy order* не работает.

**Вывод:** большой Hauler, который по design должен обнаруживать межзвёздные задания, фактически оказался ослеплён неполной записью старта. Это доказанный дефект загрузки fitting и существенный блокер для обычной логистики. **Не доказано**, что это единственный блокер доставки (дополнительно возможны покупная цена, контрактное вознаграждение, репутация, маршруты, конкурирующие цели).

## Исправление в прямых исходниках (без overlay)

`sim_db::spawner::parse_ship_fitting` сначала строит size-aware `ShipFitting::new_for_size(size, ship_id)`, затем накладывает **только явно присутствующие** слоты из исходного JSON. Следствия:

- Huge + только `comms_t2` → остается Huge `sensors_t2` и `comms_t2`.
- Huge + явно `sensors_t1` в старом сохранении → остается T1; пользовательская настройка не переопределяется.
- Маленький/средний корпус + `comms_t2` → базовые T1 sensors.
- `{}` на Huge → штатный T2 по размеру.

Никакой дополнительной валюты, cargo, контракта, исследования или открытого player API не добавлено. Старые полностью заданные fittings не переписываются.

## Gate проверки

CI `native-062-gas-sensor-fix.yml` выполняет **только один узкий блок**:

1. Четыре native Rust regression теста `sim_db` (release profile).
2. Прямая Windows сборка Genesis из `native/`, без ZIP и Python overlays.
3. Проверка игры на чистой SQLite: 8 систем, ×16, >=850 тиков, Observer/API.
4. Короткое независимое наблюдение до ~1800 тиков. Отдельно проверяется действительный `sensor_range_au>=2.0` у `ship-terran-authority-hauler-5`; настоящие события `contract_delivered` для `commodity=gas` и `destination=earth-station` выводятся в отчёт, не подменяются статусом `posted/paid`.
5. `relief_verified` остается `unknown`, пока нет причины, доказанной native receipts/A-B. При отсутствии доставки в коротком окне не заявлять исправление всей логистики.

## Граница и безопасность

Используется самостоятельная экспериментальная Git-ветка и draft PR. `main`, stable, существующие DB и пользовательский интерфейс неизменны. Другие механики (0.6.3 approval, техдерево, колонизация) не затрагивались.

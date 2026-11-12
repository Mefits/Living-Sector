# N53 — исходные корабли у станции НЕ означают занятие дока

**CODE_UNVERIFIED.** Отдельная ветка от N46; N39 production не меняется. Основа Godot N21 `ships/docking_registry.gd`.

## Проверка Rust

В замороженной `native/crates/sim_db/src/seeder.rs` initial ships INSERT устанавливает `location_name`, но **не устанавливает** `docked_at`. В `native/crates/sim_db/migrations/001_initial.sql` колонка `docked_at INTEGER` по умолчанию NULL; `sim_db/src/spawner.rs` добавляет корабль в `FacilityStorage.docked_ships` только когда при загрузке БД явно присутствует `Some(docked_at_entity)`. Значит стартовый корабль в `earth-station` не должен молча занимать док.

Frozen worlds `sol`, `nadir`, `alpha_centauri`: 24 корабля по 8, всего 15 модулей предприятий/станций и **60 док-слотов** (в каждом из трёх миров основная станция 12, ещё четыре модуля по 2). Другие пять систем не содержат стартовых флотов.

## Код

- `scripts/sim/ships/native_dock_bootstrap.gd` читает `N4 WorldRegistry` / `N40 NativeShipRoster`, регистрирует все native facility IDs с точными location/type/docking_capacity в существующем N21 авторитетном DockingRegistry, затем все N46 корабли — **undocked, not in transit**.
- Никаких автоматических RequestDock, платежей, перевозки, распределения посадочных мест, фиктивных очередей. Когда настоящая AI/команда выдаст docking request, N21 сам выбирает свободный модуль и выдаёт защищённый от повтора receipt.
- Резко неверные данные (`docked_at`/`transit` уже в seed, ID или location mismatch, отрицательная вместимость) отвергаются до выдачи результата, без мутаций исходного N46 флота.
- `tests/n53_native_dock_bootstrap_check.gd`: 24/15/60; отсутствие фантомных доков, точное явное разрешение у основной Earth station, повторный receipt не увеличивает occupancy, невозможность отлёта до undock, запрет дока в полёте, сохранение исходного флота, reject saved-state-as-seed.

## Следующий этап

Перед общей интеграцией потребуется совместное world-state сохранение N21+N46, синхронизация с действительным N14 transit и N39 production. Не использовать отдельный registry в виде второго авторитета в живой игре — настраивать один общий DockingRegistry. Godot headless тест **не выполнялся** и не должен перекладываться на пользователя по одному файлу.

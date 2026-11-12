# N62 — fail-closed preflight для реального P1 Godot

Статус: **CODE_UNVERIFIED**, пока не выполнен headless Godot. Этот блок не меняет TickRunner, checkpoint и UI и не включает экономику/ИИ.

## Реализованные проверки

1. Проверка пути главной сцены и существования исходного скрипта (штатный `ProjectSettings` и `ResourceLoader`).
2. Проверка именно исходных 8 систем, 3 фракций, 47 тел, 15 предприятий, 24 кораблей, 3 рынков, 3 записей населения. Данные берутся из `NativeData.load_current_world()`, без генерации заглушек.
3. Проверка авторитетного `TickRunner`: активна только фаза `bodies`, сохранение содержит P1 schema=1, scenario=galaxy-067, корректный tick и seed fingerprint.
4. Короткий headless regression: read-only аудит, повреждённый seed, отказ несуществующей денежной команды, два тика и атомарный отказ восстановления чужого checkpoint.

Команда для агента при наличии Godot:
`godot --headless --path godot --script res://tests/n62_runtime_readiness_check.gd`

Никаких файлов в `user://saves` тест не создаёт. Сторонних библиотек и лицензий нет: только Godot 4 built-ins.

## Источники и границы

- Замороженный Rust `native/crates/sim_server/src/engine.rs` описывает порядок фаз и единое владение AgentStore.
- Состав мира сверяется с `native/priv/galaxy/data` и P1 тестом `p0_seed_check.gd`.
- Контрольная точка Windows P1: `7b7ad3e7ba443ddccdcd5a25becaa8affc191a97`.
- Интеграционный источник: `integration/godot-47-n33-n37-20261112` @ `1e4a1e9f34fff7313ce176107890ecdbe25fc85a`.
- N62 — только preflight и негативные регрессии, **не** подтверждение Rust parity экономики, маршрутов, контрактов, ИИ или запуска Godot.

# N32 — кандидат интеграции Godot и единый Windows smoke

**Статус: CODE_UNVERIFIED.** Подготовлено к запуску пользователем в Godot 4 Standard. Никакого утверждения о корректном синтаксисе/системном паритете без реального исполнения.

## Неподвижная основа

- Ветка: `integration/godot-foundation-smoke-20261112`.
- База полного исходного дерева: PR #119 `01b3e60119effad421a7f091e2386da5e10cdd5b` (цепочка N1, N4, N13–N16, N26–N27, N30–N31 и P1).
- Составная файловая интеграция (curated Git tree, НЕ Git merge и НЕ признание всех PR принятыми) добавляет уникальные GDScript + тестовые файлы из зафиксированных SHA PR #108, #104, #111, #91, #98, #116, #112, #110, #109, #117, #105, #113, #97.
- Коллизии: сохранены N1 версии `native_data.gd` / `world_model.gd` / `RUN-P1-SMOKE.cmd`; `tick_runner.gd` с N2+N3 календарём и событиями, вручную возвращена N1 строгая валидация pause/resume; `main.gd` с N20 панелью наблюдения и N2 игровым календарём. Список только добавленных уникальных путей: 47. Полный актуальный порядок PR проверять отдельно.
- Отдельные модули производства, рынка, контрактов, логистики и управления **присутствуют в исходниках**, однако в общем TickRunner по-прежнему исполняются только настоящие орбитальные тики; остальное проверяется через **изолированные тесты**. Не считать подключённой полноценную экономику/AI/логистику только за присутствие файлов.
- Авторитетные Rust исходники `archive/rust-galaxy-067-reference` не изменяются, баланс не калиброван.

## Запуск на Windows

1. Скачать **ZIP именно этой интеграционной ветки**, распаковать весь репозиторий (включая `native/priv/galaxy/data`; не только каталог `godot`).
2. Скачать Godot 4 Standard (не .NET): https://godotengine.org/download/windows/ . Поместить исполняемый файл в `godot/Godot.exe` либо задать `GODOT_EXE`.
3. Запустить `godot/RUN-INTEGRATION-SMOKE.cmd` — быстрый основной проход из **11 тестов**. После исправления ошибок можно запускать `RUN-INTEGRATION-SMOKE.cmd all` из консоли для всех **32 обнаруженных скриптов**.
4. Журналы и `summary.txt` сохраняются в `godot/logs/integration/`. При ошибке запустить `godot/SAVE_DIAGNOSTICS.cmd`, приложить ZIP и отдельно summary, если ZIP не содержит подкаталог integration.
5. Если тесты пройдут, открыть `godot/project.godot` в редакторе и нажать F5, проверить: 8 систем/3 фракции, выбор системы, угол Земли, пауза/шаг/×16, сохранение, календарь, панель Наблюдение. Панель честно пишет о неподключённых командах.

**Успех этого теста подтверждает только конкретные выполненные проверки, не автоматически 100 задач.** Для полномасштабной приёмки необходимо один последовательный авторитетный игровой цикл, Rust/Godot golden parity, сохранение до/после реального груза/контракта, FPS ×16, производительность, ручная приёмка.

## Быстрый набор (11)

- `p0_seed_check.gd`
- `p1_tick_save_check.gd`
- `p1_audit_check.gd`
- `n2_calendar_check.gd`
- `n3_events_check.gd`
- `n4_registry_routes_check.gd`
- `n5_native_recipes_check.gd`
- `n6_paid_production_check.gd`
- `n8_integration_check.gd`
- `n23_production_tick_check.gd`
- `n31_contract_command_runner_check.gd`

## Полный обнаруженный набор (32)

1. `n10_market_check.gd`
2. `n11_ledger_check.gd`
3. `n12_population_check.gd`
4. `n13_ship_catalog_check.gd`
5. `n14_transit_check.gd`
6. `n15_cargo_check.gd`
7. `n17_construction_check.gd`
8. `n18_station_admin_check.gd`
9. `n19_faction_head_check.gd`
10. `n20_observer_check.gd`
11. `n21_docking_check.gd`
12. `n22_ship_batch_check.gd`
13. `n23_production_tick_check.gd`
14. `n24_diagnostic_check.gd`
15. `n25_order_settlement_smoke.gd`
16. `n26_contract_delivery_check.gd`
17. `n27_contract_gate_check.gd`
18. `n28_ledger_audit_check.gd`
19. `n29_docked_cargo_check.gd`
20. `n2_calendar_check.gd`
21. `n30_contract_cargo_audit_check.gd`
22. `n31_contract_command_runner_check.gd`
23. `n3_events_check.gd`
24. `n4_registry_routes_check.gd`
25. `n5_native_recipes_check.gd`
26. `n6_paid_production_check.gd`
27. `n7_needs_production_check.gd`
28. `n8_integration_check.gd`
29. `n9_inventory_check.gd`
30. `p0_seed_check.gd`
31. `p1_audit_check.gd`
32. `p1_tick_save_check.gd`

## Известные блокеры

- Эту файловую композицию невозможно проверить Godot Runtime в агентской среде.
- PR параллельно меняются; снимок основан на указанных SHA, не на «последней версии всего».
- `N20` UI остаётся наблюдателем, не симулирует внешние подсистемы.
- Команды и контракты реализованы в отдельных компонентах, но пока **не являются единым авторитетным pipeline игрового TickRunner**. Никаких фальшивых VERIFIED.
- Интеграционная ветка не должна стать `main` до smoke, инвариантов и ручной приёмки.

## Следующее

Утром пользователь запускает smoke, присылает diagnostics. Далее фиксировать runtime ошибки, подключить в едином тике основные механики и провести 3–5 golden Rust/Godot сценариев. Другие автоматизации работают отдельно, интеграционная ветка не блокирует их claims.

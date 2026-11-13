# Living Sector — единственная интеграционная ветка Godot (P2)

**Единственная текущая цель:** собрать все source-порты в одно реальное приложение, запустить Godot и исправлять возникающие ошибки *здесь*, а не открывать новую очередь N159/N160/N161.

**Branch:** `integration/godot-phase2-unified-20261113`

**Base:** `integration/godot-47-n33-n37-20261112@1e4a1e9f`

**Исходник эталона:** `archive/rust-galaxy-067-reference@6e40615`

## Физически уже сделано (13 ноября 2026)

1. База: **[P2 N158 Draft PR #248](https://github.com/Mefits/Living-Sector/pull/248)** — реально включённые Godot GUI/clock/orbits и N39 производственный tick. Подключённая одна оплаченная экономика N9: 15 исходных предприятий, 3 локации Market, 3 группы Pop, истинные запасы, зарплаты, рецепты и salvage, сохранения `user://saves/galaxy-067-p2-integration.json`. Скорость корректно меняет Rust `tick_multiplier`.
2. **159 исходных Godot PR #89–247** проинспектированы по GitHub PR-file diff; в этой ветке добавлены **225 уникальных .gd файлов** без конфликтов (плюс JSON source PR index). Исторические PR НЕ слиты в их исходные base branches, но Git blobs всех не конфликтующих новых игровых скриптов уже физически здесь. **Присутствие source file НЕ означает его выполнение в общей симуляции**.
3. Содержательное разрешение первого ключевого коллизии: `godot/scripts/sim/save_state.gd` **обновлён до N38 PR #127** — SHA-256 envelope, backward-compatibility, `.pending/.bak` восстановление и сохранение через один существующий P1/P2 интерфейс. Старые P1-сейвы читаются. Никакой отдельной SQLite или второй денежной системы не создавалось.
4. Точные коллизии входящих изменений записаны в `godot/docs/phase2/UNIFIED_IMPORT_CONFLICTS.json` (13 уникальных файлов, одна из них N38 разрешена). В частности старые версии `main.gd`, `tick_runner.gd`, `ship_tick_runner.gd`, `ship_transit.gd` не затирают действующий N158/P1 seed.
5. **Godot 4.7.2:** добавлена одноразово срабатывающая по файлу workflow `.github/workflows/p2-unified-godot-smoke.yml`. Она скачивает официальный Godot 4.7.2, запускает `--editor --import`, загружает ВСЕ `godot/scripts/**/*.gd` в `p2_unified_script_compile_check.gd` и проверяет `p2_n158_live_production_check.gd` (real seed/paid wages/stock/file save+restore). Сеть/Windows-пользователь не нужны. Тесты могут упасть, и это **настоящая работа по интеграции, а не повод объявлять успех**. При каждом следующем существенном исправлении сознательно обновлять `P2_CI_TRIGGER.txt`, чтобы не запускать тяжёлые Actions на каждый коммит. Журналы сохраняются артефактом workflow.

## Что реально исполняется и что ещё нет

| Домен | Статус |
|---|---|
| Исходный Galaxy seed, P1 orbit/clock, controls/events | Встроен в базовый Godot GUI |
| N39 реально оплачиваемое производство, 3 Market, 3 Pop, 15 Facility + запас/зарплата | Подключено в N158, запуск в CI определяет VERIFIED статус |
| N38 integrity save + N39 рынок/платежи/WorkShift checkpoint | Подключён в P2 ветке, реальный рестарт в CI проверяется |
| N151 реальные Food/Water household purchases и migration | Есть GDScript, **ещё не подключён к единому N9 ledger** |
| N150 рынок/цены/дефициты, N156 condition/repair/crew supply | Есть GDScript, **не запускаются** рядом с N39, пока нет одной authoritative commit path |
| N97/N104/N152 ship Apply/contracts/escrow, N149/N153 ship autonomy, N140/N142 fleet LOD/travel | Исходники присутствуют, **не выполняются** в единой phase execution |
| N100/N155 Hybrid Planner, N134 Director, N143 research, N154 construction/shipyard | Исходники присутствуют, но **не подключены** к реальной фракционной стратегии с подтверждёнными receipts |
| N157 full economic-frame atomic persistence | Исходники присутствуют; общего snapshot ECS ships+board+director ещё нет |

**Не считать закрытой Фазу 2** до реального единого симулятора. 10/10 из Фазы 1 относилось только к исходному покрытию.

## Порядок технического объединения здесь, без отдельных PR

**Единый мир и счета → экономический полный tick → флот+контракты → фракции/администраторы/Hybrid → полная сохранность и Rust parity.** Это не «ещё пять проектов» и не обещание 100 итераций: работа продолжается в одной ветке и одном PR с настоящими Godot acceptance results. Защищаем инварианты: один World, один Ledger, одна ContractBoard, один AgentLod, один SimCommand apply, один FileAccess save.

## Запуск

- В редакторе Godot 4.7.2: открыть `godot/project.godot` (клиент N158 подключён).
- Headless import: `godot --headless --path godot --editor --import --quit`.
- Полная проверка парсера: `godot --headless --path godot --script res://tests/p2_unified_script_compile_check.gd`.
- Проверка реальной оплаченной смены: `godot --headless --path godot --script res://tests/p2_n158_live_production_check.gd`.
- <https://github.com/Mefits/Living-Sector/actions/workflows/p2-unified-godot-smoke.yml> — единый целевой CI.

**Честная граница:** собраны исходники и запущен процесс реального headless тестирования; пока журнал CI не подтверждает PASS, код нельзя называть проверенным.

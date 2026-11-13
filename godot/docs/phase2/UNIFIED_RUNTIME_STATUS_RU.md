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

## P2 handoff — 13.11, восстановление nonce кораблей

- Commit `73b9ba7a`: `ship_transit.gd` теперь реализует `next_token()` и `restore_next_token(cursor, highest_active_token)`, на которые уже ссылается N54 `ship_tick_runner.gd`. Восстановление отклоняет повторное использование активного токена. Это **CODE_UNVERIFIED**, не включение флота в действующий N158 runner.
- CI [run 43343971908](https://github.com/Mefits/Living-Sector/actions/runs/43343971908) **CANCELLED**, не PASS: официальный Godot 4.7.2 установлен, проверка 241 preload завершилась без отсутствующих файлов, но команда editor/import не закончилась за ~9 минут; лог диагностики в artifact `14000619065`. Новых Actions не запускали. До следующего CI надо установить timeout на отдельные Godot-команды и выяснить зависание импорта.
- Следующая свободная работа: объединить флот с единственным World/TickRunner, не создавая вторую денежную систему; проверить сохранение кораблей и контрактов в одном snapshot. Scope `ship_transit.gd` освобождён, lease в `godot/docs/phase2/leases/20261113-ship-transit-token-recovery-shift11.json`.
- Windows x86_64 ZIP **ещё не создан**, скачиваемого исполняемого билда пока нет.

## P2 handoff — сохранение/загрузка интерфейса, 13.11 05:20 МСК

- Commit `7d79fb4c`: устранено расхождение путей Save/Load в `main.gd`: оба используют `P2_SAVE_PATH`, вместо загрузки чужого P1 `SaveState.DEFAULT_PATH`. При восстановлении `.bak` UI явно сообщает о резервной копии. Это реальное исправление доступности сохранённой экономики после перезапуска.
- Проверка: сверены методы `SaveState.save_runner/load_runner` и строки вызовов; Godot не запускался, статус **CODE_UNVERIFIED**. Actions не запускали, бюджет CI не расходовали.
- Lease `20261113-p2-save-load-ui-shift11b.json` освобождён. Общая сборка Windows и проверка повторного запуска по-прежнему требуются.

## P2 handoff — Windows export packaging, 13.11 05:32 МСК

- Commits `5f730e47`, `eb7957b4`: added `godot/export_presets.cfg` Windows Desktop x86_64 and `godot/scripts/phase2_package_windows.sh`. The script uses the actual Godot export templates, requires both nonempty EXE and PCK, packages README and verifies ZIP integrity; no fabricated binaries.
- No GitHub Actions triggered; no Godot binary/export templates available in this execution. **Windows ZIP is not yet built or downloadable**. Source remains CODE_UNVERIFIED.
- Next: fix cancelled CI import timeout with one bounded checkpoint run if necessary, install matching export templates and run packaging; verify actual boot, paid ticks, save/load before distributing. Lease `20261113-windows-export-preparation-second-chat-overnight.json` released.

## P2 handoff — fail-closed authoritative phases, 13.11 05:43 МСК

- Commits `c4b00a97`, `62339a23`: the sole N39 tick runner now stops subsequent phase execution and pauses on a rejected paid production / integrated population / market phase; exposes `last_phase_failure()` with phase/tick/reason. Failed partial ticks cannot be saved as healthy checkpoints. No second world or ledger.
- Cheap static parenthesis check passed; Godot runtime **not executed**. The failed tick still advances its calendar once and is deliberately not replayed. Follow-up: surface the diagnostic in UI, verify behavior in bounded Godot checkpoint. No Actions launched; no Windows ZIP yet.
- Lease `20261113-phase2-failclosed-tick-shift11c.json` released. Other workers should avoid reintroducing continue-on-error in this runner.

## P2 handoff — отображение ошибок фаз в GUI, 13.11 06:03 МСК

- Commit `389b0a0c`: `main.gd` показывает реальную ошибку `last_phase_failure()` (phase/tick/reason), запрещает возобновление и ручные шаги после отказа, а также предотвращает перезапись последнего здорового сохранения из UI. `startup_health()` теперь включает `runtime_failure` для диагностики.
- Изменён только `godot/scripts/main.gd`; авторитетный N39 World/Ledger и Runner не дублируются. Проверка: сверены вызываемые методы с `n39_native_production_tick_runner.gd`; Godot/Windows не запускались, **CODE_UNVERIFIED**. Дополнительных GitHub Actions: **0**.
- Lease `20261113-p2-runtime-failure-ui-shift11d.json` освобождён. Следующий свободный приоритет — ограниченный импорт Godot 4.7.2 с timeout и устранение группы ошибок перед финальным Windows export; параллельные работы сверять с новыми leases.
- Скачиваемый Windows ZIP пока не подтверждён.

## P2 handoff — ручной Windows export workflow, 13.11 06:22 МСК

- Commit `8473c4d6`: добавлен `.github/workflows/p2-windows-release.yml` с **только `workflow_dispatch`** (без push/PR trigger), закреплён Godot 4.7.2 и его Windows x86_64 export templates. Импорт и N158 paid-world smoke ограничены по времени, затем вызывается существующий `phase2_package_windows.sh` с проверкой непустых EXE/PCK, ZIP и SHA-256. Только после успешных стадий публикуется Actions artifact `LivingSector-P2-Windows-x64`.
- CI run `43343971908` по-прежнему CANCELLED; новый workflow **не запускался**, общий Actions-бюджет не расходован. В этой итерации нет доказательства успешного Godot import или Windows старта; ZIP **не создан**. Отдельный ручной запуск согласовать после устранения текущих import/parser проблем; затем проверить реальный артефакт и Windows boot.
- Lease `20261113-windows-export-ci-artifact-shift11e.json` освобождён. Изменён только новый workflow и координационные файлы; единый World/Ledger/Runner не тронут. Следующий свободный приоритет — runtime import/parser diagnosis, затем одна совместная проверка и публикация Windows ZIP.

## P2 handoff — 13.11 06:38 МСК, проверка авторитетной проекции населения

- Commit `7e757abd`: `unified_population_phase.gd` теперь проверяет идентификаторы и обязательные поля групп населения, неотрицательные численность/средства, структуру рынка и наличие реального продавца в едином N39 World до формирования оплаченных покупок. Обход facilities/markets детерминирован по ключам. При ошибке возвращается `ok=false`, что существующий N158 runner трактует как fail-closed, без отдельного ledger.
- Минимальная статическая проверка: файл прочитан после коммита, скобки сбалансированы, guards присутствуют. Godot runtime **не запускался**, CODE_UNVERIFIED. GitHub Actions **не запускались**; Windows ZIP не создан.
- Lease `20261113-population-phase-guard-second-chat-overnight-0638.json` освобождён. Следующая свободная работа: ограниченный import/parser checkpoint и подготовка финального Windows export; интеграция флота/контрактов остаётся открытой. Перед правками сверить свежие leases.

## P2 handoff — 13.11 06:39 МСК, восстановление GUI после загрузки

- Commit [aa650eaf](https://github.com/Mefits/Living-Sector/commit/aa650eaf8b557a06f2261bb6dea46eedfff515b4): после успешного `SaveState.load_runner` интерфейс повторно получает `worlds()` из восстановленного авторитетного World, выделяет прежнюю систему и синхронизирует `OptionButton` с восстановленным `clock.world_speed`. Если скорость не входит в предустановки, не отображается ложный множитель. Ledger, World, TickRunner, SaveState не менялись.
- Scope `godot/scripts/main.gd`; lease `20261113-save-load-map-resync-second-chat-0639.json` RELEASED. Проверено по исходным контрактам `SystemMap.set_worlds/select_system`, `clock.world_speed`; Godot не запускался — **CODE_UNVERIFIED**. GitHub Actions запусков: **0**.
- Windows ZIP не создан в этой итерации. Следующий приоритет: один ограниченный Godot import/smoke/export checkpoint после сверки свежих leases и состояния общего Actions-бюджета; не запускать CI при активной проверке другого исполнителя.

## P2 handoff — 13.11, защита загрузки повреждённых экономических снимков

- Commit [`b237444e`](https://github.com/Mefits/Living-Sector/commit/b237444e18b16905878c3a4cb2745945ebe4c940): `n158_production_runtime.gd` теперь проверяет типы вложенных объектов facility/work_shift, markets/history, populations и ledger/receipts/legs до обращения к ним как к Dictionary/Array. Повреждённый или несовместимый JSON отклоняется через `restore_checkpoint() -> false`, вместо возможного runtime exception в процессе восстановления. Одна авторитетная экономика, без новых подсистем.
- Проверка: 8 точечных guards внесены в существующий код, без удаления других фаз; GDScript Runtime не запускался — **CODE_UNVERIFIED**. Новых GitHub Actions **0**. Windows ZIP пока не подтверждён.
- Lease `20261113-n158-restore-shape-guard-automation11.json` RELEASED. Следующий приоритет — ограниченный Godot import/paid-world smoke с диагностикой предыдущего зависания, затем один Windows export.

## P2 handoff — 13.11 07:28 МСК, fail-closed проверка рынка

- Commit [`0dbbfd83`](https://github.com/Mefits/Living-Sector/commit/0dbbfd831771e607e1f799cbba8199e9b14f79f6): `unified_market_phase.gd` теперь отклоняет повреждённые строки N39 markets, неверные вложенные типы и неполный/некорректный N150 output до обращения к словарям или применения market phase. Проверяется совпадение числа рынков; прежний запрет создания stock сохраняется. Ни второго ledger, ни нового market state.
- Минимальная проверка скобок и интерфейса; Godot не запускался, **CODE_UNVERIFIED**. Actions: **0** новых запусков. Lease `20261113-market-phase-shape-guard-automation11b.json` RELEASED.
- Windows ZIP по-прежнему не подтверждён. Следующий свободный приоритет: ограниченный Godot import/parser, исправление выявленных ошибок группой и затем единый согласованный Windows export. Перед работой проверить актуальные leases.

## P2 handoff — 13.11 07:40 МСК, автоматическое восстановление мира при старте

- Commit [`79c8588f`](https://github.com/Mefits/Living-Sector/commit/79c8588fc5aca07e9a9597731f8794b2f1270da6): `godot/scripts/main.gd` вызывает единственный `SaveState.load_runner` при старте, если существует P2 checkpoint или `.bak`, до построения карты и UI-проекций. После восстановления использует единственный авторитетный N158 World/ledger и синхронизирует скорость. Повреждённое сохранение не блокирует загрузку исходного seed; ошибка видна пользователю. Никакой второй SaveState или World не создаётся.
- Проверены контракты `SaveState.load_runner`, `_sync_speed_control`, порядок инициализации UI; Godot не запускался — **CODE_UNVERIFIED**. Actions не запускались; Windows ZIP не подтверждён. Lease `20261113-p2-startup-save-recovery-second-chat-0740.json` RELEASED.
- Следующая свободная работа: локальный/ограниченный Godot import и устранение parser ошибок перед единым Windows export; флот и контракты ещё требуют подключения к общей симуляции.

## P2 handoff — 13.11 07:45 МСК, transactional save restore

- Commit [b677dd7d](https://github.com/Mefits/Living-Sector/commit/b677dd7daca4c39e7a1bdfc9c16af93e24059507): единственный `SaveState.load_runner` теперь сохраняет live checkpoint перед попытками загрузки и восстанавливает его, если `restore_checkpoint` отверг повреждённый snapshot после частичной мутации. Только после успешного rollback пробует `.bak`; при неудачном rollback сообщает критическую ошибку. `save_runner` ограничивает размер сериализованного JSON до записи на диск.
- Scope `godot/scripts/sim/save_state.gd`, lease `20261113-save-state-transactional-load-shift11-0745.json` RELEASED. CODE_UNVERIFIED: Godot Runtime не запускался, Actions запусков 0. Проверка семантики rollback с реальным N158 restore и end-to-end save/load обязательна перед объявлением билда проверенным.
- Windows ZIP ещё не подтверждён. Следующий приоритет — один ограниченный Godot import/paid-world smoke, исправление реальных ошибок и финальный Windows export. Не запускать новый CI при активном запуске другого исполнителя.

## P2 handoff — 13.11, восстановление незавершённого атомарного сохранения

- Commit [6c82236d](https://github.com/Mefits/Living-Sector/commit/6c82236d1a334792e94f37cfb7a37259ac551dc3): `SaveState.load_runner` проверяет целостный `.pending` как **последний** источник восстановления после основного и `.bak`, если процесс был прерван до promotion. Неподтверждённый pending никогда не вытесняет исправное основное сохранение/резервную копию. Ответ содержит `recovered_pending`, чтобы интерфейс мог явно сообщить об аварийном восстановлении. Не добавлены второй SaveState/World/Ledger.
- Статическая проверка: сохранён существующий порядок primary→backup, новый fallback использует прежнюю SHA-256 envelope-проверку и rollback живого состояния при отказе `restore_checkpoint`. Godot Runtime **не запускался**, CODE_UNVERIFIED. Дополнительных Actions: **0**. Windows ZIP не подтверждён.
- Lease `20261113-save-pending-recovery-automation11f.json` RELEASED. Следующий приоритет: ограниченный Godot import и единый Windows export с настоящим артефактом, с учётом общего бюджета CI.

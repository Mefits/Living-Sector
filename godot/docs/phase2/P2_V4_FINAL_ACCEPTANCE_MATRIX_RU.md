# Living Sector / P2 — В4: итоговая матрица исходного переноса и единая приёмка

**Срез исходников:** 14.11.2026, PR #249, `integration/godot-phase2-unified-20261113` · Rust Galaxy 0.6.7 — замороженный эталон.

**ЭТО НЕ ОТЧЁТ О ЗАПУСКЕ.** Никакого Godot/Windows/F5/headless/Actions в ходе В4 не выполнялось. Термины ниже означают:
- **SOURCE-WIRED** — нужный исходный домен действительно вызывает существующий единый N158/N39/N9/N104 путь на уровне кода; это **не** подтверждённое игровое поведение.
- **SOURCE-ONLY** — есть адаптер, но ещё нет подтверждённого вызова/Apply в едином runtime.
- **SOURCE-GAP** — проверяемый активный механизм оригинального Rust не найден в соответствующем пути Godot.
- **DEFERRED** — полноценная финальная проверка, которая пока не проводилась по решению пользователя.
- **SOURCE-POLICY / NOT APPLICABLE** — у замороженного Galaxy функция оригинала отключена конфигурацией; нельзя включать её «для паритета» бесплатно.

## 1. Строгие границы: один симулятор, не две игры

| Слой | Авторитет | Статус по исходникам | Что ещё доказать |
|---|---|---|---|
| Тик/порядок фаз | `tick_runner.gd::NATIVE_PHASE_ORDER` → `n39_native_production_tick_runner.gd` → `n158_production_runtime.gd` | SOURCE-WIRED | Во время прогона нет второго TickRunner или повторного платёжного Apply |
| Физические объекты, флот, рынки | `n39_native_world_production.gd::_world` | SOURCE-WIRED | Прохождение одного долгого прогонa без расхождения N15/N21/N14/рынков |
| Деньги и завершённые финансовые операции | Одна `credit_ledger.gd` через N39 | SOURCE-WIRED | Нет повторной оплаты, фантомных кошельков и расхождений после N38 |
| Контракты/escrow/фактическая выдача награды | Одна `contract_board.gd` через N39/N104/N9 | SOURCE-WIRED | Реальный контракт → загрузка → перелёт → выгрузка → N9 paid |
| Сохранение/восстановление | `save_state.gd` + N1/N39/N158 staged restore | SOURCE-WIRED | Срединный save/load рейса, стройки и позднего плана без replay |
| Источник мира | `native/priv/galaxy/data` (8 исходных миров, 3 фракции) | SOURCE-WIRED | Windows EXE+PCK+внешняя копия исходных JSON действительно загружается |

Не считать более 1000 коммитов в PR доказательством полноты или безошибочной работы. Отдельные source-файлы и сочинённые тестовые состояния не равны реальному непрерывному исполнению.

## 2. Rust Engine → Godot Phase2: инвентаризация

Активный Rust `native/crates/sim_server/src/engine.rs::run_tick_loop` проходит **bodies → bodies_regen → lod → ships → apply1 → dock_queue → drains → facilities → construction_labor → populations → markets → crisis → apply2 → factions → progression → colony → relations**. P1 перечисляет тот же порядок и отдельные snapshot/persist/broadcast. В Rust несколько стадий стоят вне `phase!` макроса (в частности drains и colony), поэтому сравнивать только имена `phase!` неверно.

| Источник Rust | Текущий Godot | Вывод |
|---|---|---|
| `tick_bodies` / орбиты планет | P1 WorldModel, NativeData + N158 resolver | SOURCE-WIRED, движение реальных объектов не подтверждено F5 |
| `bodies_regen` и auto respawn списанных кораблей | В `native/priv/galaxy/data/tuning.json` оба выключены: `regenerate_body_resources=false`, `auto_replace_retired_ships=false` | **NOT APPLICABLE** для замороженного Galaxy; не включать их |
| LOD / корабельный source BT / N146 команды | N140/N80/N81/N84/N153 → N39 `ships` | SOURCE-WIRED **частично**, end-to-end А неизвестен |
| Apply 1/2 и N15/N97/N104 оплаченные операции | Команды применяются в N39, отдельный fake apply2 не нужен | SOURCE-WIRED, требуется trace в одном непрерывном рейсе |
| **N21 `tick_dock_queue_advance`** | `unified_n21_dock_queue_stage.gd` → N39 реальная FIFO+N9 оплата → N158 `dock_queue` в штатной фазе | **SOURCE-WIRED / CODE_UNVERIFIED**; legacy manual dock и timeout N84 ещё проверить |
| `drain_pending_materializations` | N154/N151 непосредственно материализуют объект в N39, исторические квитанции N38 | SOURCE-WIRED функционально; не создавать отдельную очередь SQL |
| `drain_pending_decommissions/respawns` | N148/N152 retirement/removal через N39 и N9; replacement запрещён исходным tuning | SOURCE-WIRED для removal, free respawn NOT APPLICABLE; проверить отсутствие повторной эмиссии |
| `tick_facilities`, N156 lifecycle, N143 research, N141 labor | N39 `run_tick`, отдельные source paid stages | SOURCE-WIRED; проверить Faction → реальное финансирование и выпуск |
| `tick_populations` / `tick_markets` | N151 source consumption + N150/N131 N39 history | SOURCE-WIRED |
| **`scan_crisis_events`** | `unified_native_crisis_phase.gd` → N158 `phase == "crisis"` → N39 `apply_native_crisis_phase` → существующий сигнал | SOURCE-WIRED, runtime NOT VERIFIED |
| `faction::tick_factions`, N100/N134/N155/N121 | Head/Admin в N158 + реальные N39 Apply/plans/receipts | SOURCE-WIRED для основной цепочки, успешная автономия NOT VERIFIED |
| `colony::prepare_docks/establish` | N144/N151 B1–B3: физический dock, passengers, 600 Metals, 150 shifts, 20k paid N9 transfer; завершённый Market | SOURCE-WIRED, реальная последовательность Б NOT VERIFIED |
| `tick_relations_pass` / research/upgrades | N150 отношений + N143 research/N154 source modules | SOURCE-WIRED, нужна проверка точной очередности и оплаченного результата |
| Rust HTTP/WS/SQLite worker | Godot offline UI, N38 JSON и Windows PCK | **Другой слой исполнения**, не повод автоматически клонировать весь HTTP server внутрь Godot |

### Проверенные незакрытые границы исходников

**N21 FIFO — исходный основной цикл теперь подключён (чат №1, lease RELEASED).**
В `godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd` и `n39_native_world_production.gd` реализован исходный FIFO queue + N9 dock fee + per-facility queue in World, а N158 теперь запускает настоящую фазу `dock_queue` независимо от N140. Handoff: `20261114-chat1-n21-fifo.md`. Оставшиеся риски: N84 Dock timeout/replan, legacy ручной/отладочный Dock без оплаты, удаление/переименование пристаней, N38 midqueue restore. **Исходные вызовы не заменяют фактическую приёмку Godot.**

**P1 — автономный exploration/source N80, N103 mining.**
Существуют `unified_n80_ship_exploration_stage.gd` и source варианты, однако в проверенном N158 нет подтверждённого подключения соответствующего source-adapter как активного генератора реальной команды (на время среза Chat1 N80 lease уже RELEASED как source-only). Не заявлять реальный самозапуск исследовательских походов. Владелец: чат №1 / флот.

**N92/B4 — SOURCE-WIRED после закрытия чата №2.**
Chat2 B4 lease **RELEASED**: `unified_n92_colony_aftercare.gd` действительно вызывается через `N158 → N39.apply_native_b4_colony_aftercare → N100/N98 → N121/N104/N9`, а не прямо из N158. Состояние активных рейсов, потребление Food/Water и N154 stock читаются из канонического World. Это **НЕ** доказанный физический сценарий в Godot. После закрытия чата №2 чат №3 связал N147 рабочую миграцию с текущим N134 Head и добавил **точный Rust N113 retain_or_switch** для проверенных source-конкурентов: превосходство 1.20×, два РАЗНЫХ реальных стратегических цикла, сохранение pending в N39 без N9/N104 и законный переключатель на физический пассажирский контракт только после подтверждения. В следующем блоке N113 подключён чистый `unified_n113_original_candidates.gd`: текущая готовность research из N143, активное/новое expansion из N144, прежний supply с реальной повторной котировкой N154/N111. Подтверждение миграции требует соседних стратегических циклов `60×mult`. Если старый supply не удаётся достоверно перекотировать, он **остаётся защищённым**; N109/N110 исследовательские мандаты и уставы теперь имеют единую сохранённую политику N39, используются N143 для реальной проверки оплаты и N113 для исходного приоритета только при действительном delegated-разрешении. Пользовательский вход управления ещё не подключён в N158; экономические мандаты и старые логистические заявки требуют отдельной сверки исходного паритета. Все эти новые пути ещё не выполнялись в Godot.

**P2 — диагностика списка фаз исправлена в исходниках.**
После освобождения N158 `implemented_phases()` уже содержит фактически выполняемые `crisis` (коммит `6f6a2a4`) и `dock_queue` (handoff Chat1 N21). Проверка фактического исполнения в Godot остаётся отложенной. `bodies_regen` выключена исходным tuning; не включать ради совпадения списка N1.

**P1 — непрерывная автономная вертикаль clean seed.**
Ранее зафиксированы отсутствие funded N104 заявок и отправлений на тике 652 в предоставленном пользователем прогона. Даже если N153/флот/доставка проходят искусственный fixture, «игра сама торгует и летает» нельзя считать подтверждённым. Source freeze запрещает накручивать спрос, удалять ресурсы или создавать бесплатные корабли ради видимости активности.

## 3. Финальная согласованная приёмка А/Б/В/Г — один цикл ПОСЛЕ SOURCE_INTEGRATION_COMPLETE

| Макрогейт | Одно общее доказательство | Запрет на ложный PASS |
|---|---|---|
| **А: реальный автономный груз** | Head/market shortage в изолированном сценарии, настоящий N104 N9 escrow, выбор N153, фактический N14 маршрут, N21 FIFO, N15 warehouse/hold и single N9 paid; checkpoint посреди маршрута и после оплаты | Не перемещать корабль в тесте непосредственно; не заменять контракт ручной загрузкой |
| **Б: колония/стройка** | Реальное решение о N151, настоящие N104 пассажиры и N15 Metals в количестве 600, 150 оплаченных N141 смен, исходный N151 dock → тот же station+market и 20k N9; N38 restore | Никаких выданных из воздуха людей, товаров, treasury, маршрутов и рынков |
| **В: глава/администраторы/ИИ** | N100/N134 выбирают полезное направление из живого N39, N121 создаёт один реальный исполненный/оплаченный action, N156/N143/N150/N92 читают и обновляют тот же мир | Не считать preview/план или красивую сводку исполнением; проверять immutable receipts |
| **Г: один кандидат Godot 4/Windows** | Полный Godot parser/import, main.tscn, ограниченный 10/100/1000+ tick soak, midflight + post-delivery N38, один ZIP x64, реальный запуск из распакованной папки | Не считать наличие workflow/ZIP успешным запуском до выполнения |

Уже существуют `.github/workflows/p2-unified-godot-smoke.yml`, `p2-windows-release.yml`, `godot/export_presets.cfg`, `godot/scripts/phase2_package_windows.sh`. В workflows закреплена Godot 4.7.2; релизный пакет должен содержать EXE + PCK + неизменённые `data/galaxy`. Пакетный скрипт проверяет SHA каждого исходного JSON и заголовок Windows PE x64, но всё это пока **авторские исходники, не выполненные проверки**. Требуется сохранить Windows-пользовательское описание, что Godot версия соответствует импортной конфигурации.

## 4. Практический порядок

1. N21 FIFO, N80/N103 и N92/B4 получили основные исходные связи, но end-to-end исполнение ещё не проверено. Провести оставшийся source audit N84 Dock timeout, старого manual Dock и физического N38 midqueue.
2. N113 `retain_or_switch` теперь получает исходные текущие проверки N143 research, N144 expansion и N154/N111 предыдущего supply при его наличии в source-каталоге. Верифицировать живым тестом N38 границу между циклами; source-порт N109/N110 исследовательских директив, устава и оплаченных квитанций теперь подключён внутри N39/N143/N113. Остаются UI-команды в N158, экономический charter/economic mandate и старый supply вне N154; без выдуманных оценок.
3. Одним offline read-only проходом выполнить **только в конце переноса**: `python3 godot/tools/p2_v4_source_gate.py --require-complete --json`. Его `SOURCE_LINK_PRESENT` — проверка связей, а не Godot PASS.
4. При отсутствии SOURCE-GAP зафиксировать `SOURCE_INTEGRATION_COMPLETE` с SHA. Только тогда объединённая проверка существующих Godot smoke, реального GUI и Windows RC. Устранить реальные parse/runtime FAIL по логам, не запускать десятки Actions на каждую правку.
5. Отдельно **после** полного переноса — пакет пользовательских решений по балансу и механикам. Во время P2 ни один его пункт не менять.

**14.11 поздний финальный source-срез / переход к единой приёмке.** N158 теперь имеет один явный `request_faction_policy` → N39 для установки/отмены исходных research/economic mandates и изменения faction charter. Экономический мандат хранится в одном N39 World/N38 и принимается только для реально принадлежащей фракции станции; `NativeMandatePolicy` запрещает произвольный тип товара/бюджет. Однако **платёжная ветка экономической директивы `N109/N110 → source N111 quoted right action → N104/N9 paid → counters` ещё НЕ доказана и не помечается SOURCE_WIRED**: добавление безопасной возможности задавать цель не равняется выполнению её физическим автономным планировщиком. Отсутствующие переоценки старых N135/N121 supply-коммитов также не подменяются выдуманными котировками. Код-ветка помечена RC candidate **только для финального теста**, не SOURCE_INTEGRATION_COMPLETE. Один smoke-триггер зафиксирован в `godot/docs/phase2/P2_CI_TRIGGER.txt` (commit `40bfff2`); реальный результат Godot/Windows до получения CI-логов **UNKNOWN**.

**Обновлённый итог В4:** N92/B4, N147 проверяемая стратегия N113→N134, N21 FIFO и реальные фазы `crisis`/`dock_queue` source-wired. Остались проверка живого соперничества стратегий (N143 research/N144 expansion/N154 prior supply уже подключены к N113; неизвестные исторические логистические котировки и ещё не подключённый UI/экономический policy-контроль требуют паритета), N84 таймаутов, legacy docking, N38 длительных рейсов и один финальный Godot/Windows gate. Ни один макрогейт А/Б/В/Г не имеет реального Godot PASS; балансные правки отложены.

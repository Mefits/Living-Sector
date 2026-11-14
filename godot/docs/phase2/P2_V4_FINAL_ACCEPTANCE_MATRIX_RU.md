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
| **N21 `tick_dock_queue_advance`** | `godot/scripts/sim/ships/docking_registry.gd` сейчас возвращает `no_available_dock`; `n158_production_runtime.gd` не выполняет `dock_queue` | **SOURCE-GAP: существенный блокер полного Rust parity** |
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

**P0 — N21 FIFO докование, подтверждённое исходное отличие.**
В `native/crates/sim_server/src/engine/apply.rs::apply_request_dock_typed` и `tick_dock_queue_advance` присутствуют: очередь при полном доке; соблюдение места в FIFO; отсутствие queue-jump при освобождении слота; удаление устаревших и неплатёжеспособных заявок; реальная плата на admission через существующие деньги; продвижение головного корабля **каждый тик независимо от LOD**. В `godot/scripts/sim/ships/docking_registry.gd` нет хранимой `dock_queue`; при полной вместимости немедленно возвращается `no_available_dock`, а `_execute_integrated_phase` N158 не обрабатывает фазу `dock_queue`. Это **не** можно объявить перенесённым по наличию N21 docking API. Следующий ответственный за флот должен перенести настоящую FIFO-природу внутрь канонического N39 FacilityStorage + N9 fee/receipts + N38 и N1/N158 phase `dock_queue` без второго DockingRegistry, прежде чем делать финальный release.

**P1 — автономный exploration/source N80, N103 mining.**
Существуют `unified_n80_ship_exploration_stage.gd` и source варианты, однако в проверенном N158 нет подтверждённого подключения соответствующего source-adapter как активного генератора реальной команды (на время среза Chat1 N80 lease уже RELEASED как source-only). Не заявлять реальный самозапуск исследовательских походов. Владелец: чат №1 / флот.

**P1 — N92/N134 экономический aftercare новых колоний.**
`unified_n92_colony_aftercare.gd` есть, но во время аудита Chat2 B4 lease **IN_PROGRESS**: ещё нужно подтвердить `N92 source goals → Head/N100/N121 → real N39 action`. Это отдельное условие живой колонии, не равно уже созданной B3 станции. Владелец: чат №2 / колонии.

**P2 — `implemented_phases()` врёт диагностике.**
`n158_production_runtime.gd` действительно выполняет `if phase == "crisis"`, но `implemented_phases()` перечисляет только bodies/ships/facilities/populations/markets/factions/relations, без crisis. Нельзя ориентироваться на список как на факт отсутствия кода. Исправить после освобождения файла чатом №2, не переписывая реальную фазовую логику.

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

1. Погасить P0 FIFO N21 в коде, не затрагивая чужие lease без релиза. Затем завершить N80 и N92 source-only adapters через настоящий N39/N158.
2. Уточнить список `implemented_phases`; после освобождения общего файла включить `crisis` в реально выполняемые диагностические фазы.
3. Одним offline read-only проходом выполнить **только в конце переноса**: `python3 godot/tools/p2_v4_source_gate.py --require-complete --json`. Его `SOURCE_LINK_PRESENT` — проверка связей, а не Godot PASS.
4. При отсутствии SOURCE-GAP зафиксировать `SOURCE_INTEGRATION_COMPLETE` с SHA. Только тогда объединённая проверка существующих Godot smoke, реального GUI и Windows RC. Устранить реальные parse/runtime FAIL по логам, не запускать десятки Actions на каждую правку.
5. Отдельно **после** полного переноса — пакет пользовательских решений по балансу и механикам. Во время P2 ни один его пункт не менять.

**Итог В4 по исходникам:** работу по переносу нельзя объявлять полной, пока остаются как минимум P0 N21 dock FIFO, P1 N80/N92 source-only связки и P2 диагностический phase inventory. Наличие остальных мостов не доказывает поведения без единого реального запуска.

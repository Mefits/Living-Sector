# Living Sector — ночная очередь автономной разработки Godot

**СЧЁТЧИК ОБРАБОТКИ (2026-11-12, не путать с VERIFIED):** N1–N47 — **46 блоков обработаны и переданы в код/PR**, **1 блок (N39) IN_PROGRESS**. Это выполненная работа по источникам/коду/документации, не подтверждение игры в runtime. Из новых N33–N47 в текущую интеграционную ветку PR #128 добавлены N33–N37 (**5**); N38 и N40–N47 (**9**) пока в отдельных PR, N39 разрабатывается. Никаких пользовательских тестов до большой сборки. Прямые данные: claims/Nx.json, GitHub PR и таблица ниже, а не цифра VERIFIED.


**АКТУАЛЬНАЯ ОПОРНАЯ ТОЧКА НА 12.11.2026**: пользователь успешно запустил Godot 4.7.2, проверил карту и переключение систем. Зафиксирован неизменяемый checkpoint `checkpoint/godot-p1-windows-verified-20261112` @ `7b7ad3e7ba443ddccdcd5a25becaa8affc191a97`. Новые совместимые Godot-блоки готовить относительно актуального `integration/godot-47-n33-n37-20261112` (PR #128) или его преемника, предварительно проверив исходники и зависимости. **Прочесть [CANONICAL_GODOT_BASELINE_RU.md](CANONICAL_GODOT_BASELINE_RU.md) ДО выбора новой кодовой ветки.** Устаревшие фразы ниже про PR #87 и отсутствие любого Godot Runtime относятся к прежнему снимку истории; не принимать их за актуальный статус. Claim-протокол остаётся обязательным; пользовательская приёмка раз в ~20–30 этапов, полным ZIP и одним запуском, без патчей по файлам.


**Единая координационная ветка:** `feature/godot-nightshift-20261112` (резервирование/очередь/журнал). **Рабочие изменения:** отдельная ветка и PR для каждого занятого блока, чтобы второй чат мог работать параллельно.
**Неподвижный исходный эталон:** `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`.
**Предыдущая точка работы:** PR #87 `feature/godot-p1-ticks-orbits-saves`, базовый P1-A checkpoint сделан, **реальный запуск в Godot ещё не проверен**.
**Единый журнал обычного переноса:** [MIGRATION_TRACKER_RU.md](MIGRATION_TRACKER_RU.md).
**Методы выбора решений:** [GODOT_TOOLING_DECISIONS_RU.md](GODOT_TOOLING_DECISIONS_RU.md), [GAMEDEV_KNOWLEDGE_BASE_RU.md](GAMEDEV_KNOWLEDGE_BASE_RU.md).
**Важное решение о времени:** [INDUSTRY_TICK_ARCHITECTURE_RU.md](INDUSTRY_TICK_ARCHITECTURE_RU.md): один игровой тик + разная периодичность + события. **1 игровой час/тик только кандидат**, не закреплять как окончательный баланс без сравнения исходных длительностей Rust.

## Текущее состояние на старте ночной смены — 12.11.2026

- **P0: 3/9 VERIFIED** (архив и данные), 4 CODE_UNVERIFIED, 1 IN_REVIEW, 1 TODO.
- **P1: 0/9 VERIFIED**, есть код модели, времени, орбитального шага, первых сохранений и тестов, без запуска Godot.
- **Все этапы: 3/100 VERIFIED**. P10 — 5 будущих задач, не обязательный паритет.
- Ветка PR #87 **не считается завершённой на runtime-уровне**: не было Godot executable; это **закрытый по написанию кода блок P1-A, ожидающий Godot runtime-проверки**. Не пытаться «выполнить всё P1» авансом.
- Сторонние плагины установлены: 0. Не добавлять GUT/LimboAI до соответствующей маленькой проверки.
- В репозитории уже есть `godot/RUN-P1-SMOKE.cmd` и `godot/SAVE_DIAGNOSTICS.cmd`; не пересоздавать их каждый запуск.

## Ночной режим без Godot Runtime

**На 12.11.2026 на стороне агентской среды нет установленного Godot; пользователь спит, его ПК недоступен. Поэтому нельзя делать ручную Windows/Godot-приёмку условием перехода к следующим блокам.** Ночью выполнять полноценную разработку исходников, проверки seed/Rust-формул, статические аудит/синтаксис и подготовку коротких локальных smoke-тестов. **Godot Runtime/визуальный тест остаётся `CODE_UNVERIFIED`**, пока его действительно не запустили. Не писать «ждём пользователя» и не тратить полноценную итерацию на повторное ожидание того же теста. Если в конкретном запуске в его собственной среде неожиданно появился реальный Godot executable, разрешается короткий headless-тест с логом; не предполагать это заранее. Не полагаться на сохраняемость среды между автоматическими запусками.

## Обязательный алгоритм каждого автономного запуска

1. **ЕЩЁ ДО исследования или первого изменения кода зарезервировать один блок:** использовать [обязательный протокол claim](nightshift/CLAIM_PROTOCOL_RU.md). Создать `godot/docs/nightshift/claims/Nx.json` **через GitHub create_file на общей координационной ветке**, с `status: IN_PROGRESS` и владельцем, затем немедленно поставить `IN_PROGRESS` в таблице этой очереди и добавить запись о старте в [журнал](NIGHT_SHIFT_LOG_RU.md). Если claim уже существует или create_file конфликтует — **не начинать этот блок**, перечитать GitHub и выбрать другой. Claim приоритетнее таблицы.
2. **Сначала прочитать с GitHub свежее состояние**: эту очередь `godot/docs/NIGHT_SHIFT_QUEUE_RU.md`, `godot/docs/NIGHT_SHIFT_LOG_RU.md`, [MIGRATION_TRACKER_RU.md](MIGRATION_TRACKER_RU.md), текущие GitHub PR и исходники затрагиваемых Rust-модулей. **Не исходить из того, что текст предыдущего чата — текущее состояние**.
3. Если другой агент/человек изменил ветку, прочитать актуальный SHA, не переписывать их коммиты. Если задача выполнена в GitHub, **перейти к следующей**, не повторять.
4. Взять **не менее одного существенного связанного блока из 3–5 задач**, примерно соответствующий нижеприведённым направлениям. Не ограничиваться одним мелким файлом/одной перестановкой кода. Если блок слишком крупный, закончить один полноценный вертикальный срез (работающая логика + тест + отчёт).
4. Перед кодом проверить **как решается задача в Godot штатными средствами**, затем у зрелых разработчиков/в документации/референсах (Factorio, Victoria 3, RimWorld там, где релевантно); проверить библиотеки и лицензию. Выбрать наиболее простой **подходящий для больших масштабов** способ. Не проводить длинное исследование там, где стандартное решение очевидно.
5. **Переносить семантику из Rust**: названия/ID, рецепты, периоды, реальный расход денег/ресурсов, порядок действий, инварианты. Дизайн «1000 лет», альтернативы T4 и предложения в docs не считать работающим кодом. При рефакторинге не менять баланс молча.
6. **Использовать GitHub для реальных изменений**: править код `godot/`, короткие тесты и документацию в собственной рабочей ветке от актуальной Godot-базы; данные о бронировании, очередь и журнал обновлять только в общей `feature/godot-nightshift-20261112`. Обновить этот файл (следующий блок и примечания), `NIGHT_SHIFT_LOG_RU.md`, и основной `MIGRATION_TRACKER_RU.md` в той же ветке. Ни один запуск не должен заканчиваться только устным советом, если GitHub доступен.
7. **Проверять ровно необходимое**: Godot headless/короткие тесты, если Godot реально доступен. Если недоступен, делать разумную статическую проверку и честно писать `CODE_UNVERIFIED`, продолжая перенос. Не проводить тяжёлые Rust компиляции, часы стресс-тестов, платные GitHub Actions или автосборки Windows.
8. Обновить чек-лист **по доказательствам**: `VERIFIED` только если действительно выполнены критерии и есть успешный тест/лог; `CODE_UNVERIFIED` если код создан без запуска; `IN_REVIEW` если только частичный перенос. В **каждом результате обязательно указать «Текущее состояние»: P0, P1, общий N/100, изменённые файлы/коммиты, что осталось и следующую задачу**.
9. **Не сливать PR, не менять main/stable/Rust archive, не force-push, не удалять старые исходники и не включать сторонние бинарники без явного решения.** Если GitHub требует подключения/разрешения — сообщить об остановке, не изображать выполненную работу.
10. Ограничение на количество запусков снято по запросу пользователя: **задания повторяются каждые 65 минут, пока пользователь их не отключит**. Каждый запуск — самостоятельная полноценная итерация; допускается последовательно выполнить несколько отдельных забронированных блоков. Не создавай дополнительные автоматизации и не меняй расписание самостоятельно.

## Размер очереди и скорость выполнения

**N1–N8 — стартовые приоритеты, НЕ лимит.** Сейчас заранее описаны **N1–N20**, а полная работа идёт по [трекеру из 100 задач](MIGRATION_TRACKER_RU.md). **Число запусков автоматики не ограничено восемью и не равно числу рабочих блоков.** За один запуск нужно закончить хотя бы один полноценный блок; если он закончен, ресурсы и контекст позволяют, разрешено последовательно взять **дополнительный независимый блок**, заново зарезервировав его и зафиксировав результат. Не разбивать мелочи на искусственные Nx ради цифр.

Если все N1–N20 уже заняты или завершены, разрешено **создать N21, N22 и далее** из ещё не перенесённых задач [основного трекера](MIGRATION_TRACKER_RU.md), предварительно сверив их с актуальными PR и claim-файлами. Сначала зарезервировать следующий уникальный `Nx.json` через GitHub `create_file` в общей ветке, затем записать соответствующую строку в очередь, зависимости и источник Rust. При гонке IDs/claims повторить чтение; чужой claim не перезаписывать. Не создавать дубликаты уже занятой механики и не обходить реальные зависимости. Если нет независимой готовой работы, зафиксировать блокировку вместо формальных задач.

**N8 — промежуточный контроль**, а не конец работы. Ни восьмой блок, ни восьмой запуск не останавливают дальнейшую работу; расписание действует до ручного отключения.

## Последовательность следующих крупных блоков

Отмечать каждый блок `TODO`, `IN_PROGRESS`, `CODE_UNVERIFIED`, `VERIFIED` или `BLOCKED`. Две изначально написанные фазы не подтверждать без запуска Godot.

| № | Приоритетный крупный блок | Критерий завершения | Статус |
|---|---|---|---|
| N1 | **Статический аудит и исправления P0/P1-A без Godot:** проверить исходники GDScript, JSON, формулы Rust, некорректные ссылки/типы, целостность save/restore; доработать самодостаточные smoke-тесты для будущего запуска на ПК | PR #90: 47/47 native orbit records statically validated; input/command boundaries + third smoke. Godot runtime still required. | CODE_UNVERIFIED — third-chat-overnight |
| N2 | **Игровой календарь:** единый `SimTick`, разница между игровым часом и реальным TPS, кадровое ускорение, настраиваемая длительность тика и маппинг старой формулы | В UI/снимке есть игровой календарь; один и тот же мир не меняет экономический баланс от изменения частоты FPS | CODE_UNVERIFIED |
| N3 | **Cadence + deterministic events:** распределённые интервалы разной периодичности, очередь событий по `due_tick/phase/entity_id/sequence`; защита от дублей/отмены | Изменение FPS/скорости при одинаковом числе игровых тиков даёт один и тот же порядок событий; короткий save/load тест | CODE_UNVERIFIED — PR #91, second-chat-overnight |
| N4 | **World registry:** реальные ID кораблей, станций, рынков, фракций и локаций; маршрутный граф с `travel_routes[].distance`, связность/навигация/порядок; стабильная сериализация | Не потерян ни один объект seed; понятна разница между длиной экрана и транспортным расстоянием; тест кратчайшего пути | CODE_UNVERIFIED — PR #92, overnight-scheduler |
| N5 | **Нативные товары и рецепты:** точно извлечь все Rust `commodities.rs`, `recipes.rs` и тировые/модульные правила в данные и операции Godot | Тест одинакового состава товаров и 2–3 рецептов с точными входами/выходами без искусственных ресурсов | CODE_UNVERIFIED — PR #93, second-chat-overnight |
| N6 | **Экономический вертикальный срез:** настоящая партия выпуска с входами/выходами/складом, учётом работника и фондов оплаты в Rust-порядке | Один короткий сценарий, где недостаток входов/денег блокирует выпуск, склад/казна обновляются единожды | CODE_UNVERIFIED — PR #100, overnight-scheduler |
| N7 | **Население/рынки/производство:** выборочно связать реальные производственные фазы и потребности, не теряя оплату и физический смысл | Простой кризис еды/воды и восстановление с реальными причинами, без невидимой передачи грузов | CODE_UNVERIFIED — PR #104, overnight-scheduler |
| N8 | **Интеграционный контроль после P0→P2:** сопоставить версии, исправить несовместимости, передать список готового к утреннему тесту | Сводный технический handoff без остановки дальнейшего переноса; не объявлять ночь законченной после N8 | CODE_UNVERIFIED — PR #103, second-chat-overnight |
| N9 | **P2: товары и экономика данных:** требования/типы складов, лимиты, входные и выходные партии, сравнение с Rust-источниками | Реальные структуры, запрет создания товара, короткие проверки граничных случаев; не повторять N5 | CODE_UNVERIFIED — PR #96, overnight-scheduler |
| N10 | **P2: цены и рынок:** native price_engine, история цен, заявки и расчёт спреда | Формулы и порядок операций из Rust, детерминированные тесты; требует N5/N9 | CODE_UNVERIFIED — PR #98, second-chat-overnight |
| N11 | **P2: расчёт зарплат и денег:** финансовый ledger, проверка доступности средств, подтверждения операций и инварианты | Одна оплата = одна запись, отсутствие отрицательного баланса; для будущего производства N6 | CODE_UNVERIFIED — PR #94, second-chat-overnight |
| N12 | **P2: население и потребности:** реальные food/water/crew/labor циклы, пороги и изменение состояния | Нативные интервалы/потребление из Rust, никаких вымышленных жителей/ресурсов; требует N5/N3 | CODE_UNVERIFIED — PR #97, second-chat-overnight |
| N13 | **P3: параметры кораблей:** классы, размер, cargo/fuel/crew, модели статуса и исходные ID | Полный каталог характеристик Rust + компактное хранение, без сотен отдельных Nodes; опирается на N4 | CODE_UNVERIFIED — PR #95 |
| N14 | **P3: движение кораблей:** route progress, сегменты, стыковка, топливо, инвалидация события прибытия | PR #99: directed transit, Rust velocity/fuel, snapshot, token; docking still pending; requires N4/N13 | CODE_UNVERIFIED — PR #99 |
| N15 | **P3: инвентарь грузов и доставка:** загрузка/разгрузка, вместимость, транзакции склада и контрактов | Невозможны перевозка сверх трюма и двойная выгрузка; требует N9/N13/N14 | CODE_UNVERIFIED — PR #101, second-chat-overnight |
| N16 | **P3: контрактная книга:** типы договоров, статусы, резервирование средств, исполнение и возвраты | Инварианты escrow, истечения и idempotence по Rust; требует N11/N15 | CODE_UNVERIFIED — PR #102, second-chat-overnight |
| N17 | **P4: строительство и производственная цепочка:** стройплощадки, материалы, трудовые затраты, слоты станций | Реальная незавершённая стройка, затем завершение только после выполнения условий; требует N6/N11/N15 | CODE_UNVERIFIED — PR #105, second-chat-overnight |
| N18 | **P5: автономные администраторы:** существующие правила station/production_chain/options и исполнение распоряжений | Одно проверяемое решение администратора с реальными причинами; требует N6/N17 | CODE_UNVERIFIED — PR #106, second-chat-overnight |
| N19 | **P5: фракционные решения Главы:** scoring/память целей, кризисные приоритеты, ограничение полномочий | Несколько альтернатив и объяснимая смена приоритета, без фиктивного AI-снапшота; требует N10/N12/N18 | CODE_UNVERIFIED — PR #107, second-chat-overnight |
| N20 | **P6/P7: управление и наблюдение:** игровой интерфейс реальных контрактов/производства/AI + существующие исследования | Управление читает одну модель, показывает недоступность и фактические ресурсы; требует соответствующих N6/N16/N19 | CODE_UNVERIFIED — PR #108, overnight-scheduler |

| N21 | **P3: детерминированная стыковка/отстыковка:** завершение N14 docking и запреты операций в полёте | Rust parity, безопасные переходы, save/load и smoke; зависит от N14/N15 | CODE_UNVERIFIED — PR #109, second-chat-overnight |

| N22 | **P7-04: пакетная отрисовка кораблей:** один CanvasItem, culling, стабильный порядок, данные отдельно от SceneTree | Множество кораблей без отдельных Node; короткий headless smoke | CODE_UNVERIFIED — PR #110, second-chat-overnight |

## Важные границы и подсказки

- **Предпочтение:** глубоко завершённый работоспособный срез > пять заглушек и «готовая архитектура».
- На P1 сейчас **1 тик = 1 игровой час ещё не закодировано**. Проверь точные значения `orbit_period`, `tuning.json`, рецептов, длительности полёта, прежде чем заменить legacy `tick_scale`. Сохранить обратимую адаптацию или migration для checkpoint v1.
- Расписание задач и нагрузку распределять равномерно: `hash(entity_id) % period` допустим только если не меняет смысловые даты платежа/потребления; критичные финансовые события выполняются точно в срок, а не «примерно».
- Не подменять AI Главы простым BT, физическую перевозку мгновенной записью в склад, реальный прогресс исследований UI-анимацией.
- Для тысяч кораблей модель/renderer раздельно, пакетная отрисовка по необходимости; не создавать отдельный тяжёлый `Node2D` на каждую сущность.
- Весь исходный Rust зафиксирован, [793 файла SOURCE_INVENTORY.json](SOURCE_INVENTORY.json), уникальные ассеты не выбрасывать.

## Кто может изменить очередь

Пользователь может изменить этот файл/порядок блоков в ветке Godot. **Новый запуск обязан уважать текущее содержимое**, даже если оно отличается от изначального плана.

**При двух параллельных чатах:** существующий `claims/Nx.json` блокирует повторную работу независимо от статуса Markdown. Никаких «беру N2» только словами — первый GitHub commit обязан быть claim `IN_PROGRESS`.

**Ночные запуски не гарантируют успешный код/коммиты заранее.** Если коннектор/движок недоступен, зафиксировать препятствие в отчёте, не имитировать исправления. Если блок занят, перейти к следующему доступному; после завершения блока при наличии времени можно зарезервировать и выполнить следующий полноценный блок.

| N23 | **P1/P2: интеграция производства с TickRunner:** реальная фаза facilities, однократная смена, сохранение, headless smoke | Исполнение только в нужной фазе, без повторных выплат/товаров, с корректным restore; зависит от N3/N8 | CODE_UNVERIFIED — PR #111, second-chat-overnight |

| N24 | **P1-07: детерминированные read-only снимки/диагностика мира** — стабильная сводка сущностей и инвариантов, без изменений экономики | Идентичные снимки при одинаковом состоянии, без мутаций; headless smoke; P1-A/N4 зависимости | CODE_UNVERIFIED — PR #112, overnight-scheduler |

| N25 | **P2-05: orderbook settlement** — matching native orders, physical stock and money conservation, idempotent receipts, save/load | One settlement consumes actual inventory and buyer funds, credits seller once; Rust order_book.rs; depends on N9/N11 | CODE_UNVERIFIED — PR #113, second-chat-overnight |

| N26 | **P3 contract physical delivery settlement:** bind cargo unload receipt to escrow payout, reject replay/partial/wrong location; N15/N16 dependencies | Real unload before paid, idempotent save/load and headless smoke | CODE_UNVERIFIED — PR #114, second-chat-overnight |

N26 outcome: [draft PR #114](https://github.com/Mefits/Living-Sector/pull/114) — CODE_UNVERIFIED; physical receipt gate written, headless test not run. Direct N16 board transition methods remain an integration boundary; route all production callers via N26 coordinator.

| N27 | **P3/P2: authoritative contract delivery gate:** eliminate direct payout bypass and enforce N26 physical receipt on all contract settlement callers | Wrong ship/location/amount and duplicate receipt cannot release escrow; save/load parity; depends on N26/N16/N15 | CODE_UNVERIFIED — PR #115, second-chat-overnight |

| N28 | **P8-03: read-only ledger reconciliation** — deterministic audit of balances, transfer receipts and conservation; Rust money parity; N11 dependency | Report anomalies without mutation; tamper/replay smoke; no invented balances | CODE_UNVERIFIED — PR #116, overnight-scheduler |

| N29 | **P3 docking/cargo authoritative gate:** N21 docking state + N15 cargo transfer, fail-closed location, replay and save/load smoke | N21 PR #109, N15 PR #101; Godot runtime pending | CODE_UNVERIFIED — PR #117, second-chat-overnight |

| N30 | **P8/P3: cross-component contract/cargo audit** — read-only reconciliation of escrow, cargo receipts and payout transitions; N26/N27/N29 dependencies | Tamper/replay/snapshot smoke and no mutation | CODE_UNVERIFIED — PR #118, second-chat-overnight |

N30 outcome: [draft PR #118](https://github.com/Mefits/Living-Sector/pull/118) — read-only contract/cargo/escrow audit, tamper/replay/save smoke; Godot not run. Next: N31 runtime-oriented integration and recipient provenance after checking claims.

| N31 | **P3/P8: deterministic contract command dispatcher:** N27/N30 physical receipt and escrow checks, sorted tick commands, replay guard and restore | Draft PR #119, opt-in dispatcher; N3/N23 integration pending | CODE_UNVERIFIED — second-chat-overnight |
| N32 | **Интеграционная ветка + единый Godot smoke для Windows:** выбрать безопасный стек зависимостей ночных PR, сформировать недеструктивную интеграционную ветку, подготовить один CMD для последовательных проверок и точный handoff | PR/ветка с кодом, runnable smoke без Godot Runtime в агентской среде; список включённых PR/отложенных конфликтов; без merge в main | CODE_UNVERIFIED — PR #120, interactive-integration-chat |

| N33 | **P8: интеграционная приёмка N32:** fail-closed smoke runner, машинный JSON-отчёт, проверка обязательных тестов и handoff Windows | PR #121: 11/11 required tests present, 32 scripts in Git tree; Godot/PowerShell not executed | CODE_UNVERIFIED — PR #121, overnight-scheduler |

| N34 | **P8 integration smoke integrity:** audit N32/N33 runner, validate command/test paths and fail-closed handoff | Integration smoke cannot silently skip missing tests; static checks and headless preparation; N32/N33 | CODE_UNVERIFIED — PR #123, second-chat-overnight |

| N35 | **P1/P3: authoritative contract tick integration:** connect N31 commands to the sole simulation tick phase; prevent duplicate execution and persist queue | N31/N3/N23; fail-closed replay/save smoke; no economy bypass | CODE_UNVERIFIED — PR #124, second-chat-overnight |

| N36 | **P8: Godot 4 compatibility of N32 integration** — startup/parser audit, minimal fixes and smoke | Integration scripts parse on current Godot; no unverified VERIFIED claims | CODE_UNVERIFIED — PR #125, second-chat-overnight |
| N37 | **P0-08: аудит ассетов и лицензий Rust → Godot:** реестр медиа/шрифтов и происхождения, явные ограничения переноса, воспроизводимая проверка | PR #126: 97 SHA/size records, static 97/97 PASS; unknown rights blocked, no media copied | CODE_UNVERIFIED — PR #126, overnight-scheduler |

| N38 | **P1/P8: deterministic checkpoint integrity:** guard save schema, exact replay and corrupt checkpoint rejection; Rust parity, Godot smoke | Fail-closed checkpoint and restoration, deterministic checksum, no state mutation on failure | CODE_UNVERIFIED — PR #127, second-chat-overnight |

| N39 | **P1/P2: live production world bridge:** connect N23 paid facility simulation to actual native station inventories, workers, and wallet references at the single Godot tick, without double pay/creation or event regressions; guarded snapshot/restore | One real facility production tick changes stock and balances once; insufficient materials/funds block production, orbits/events preserved | IN_PROGRESS — interactive-chat, claim N39 |

| N40 | **P1/P3: live ship transit world bridge**: N13/N14 реальные seed-корабли, тики, топливо, рейсы без телепортации или выдуманных грузов; не затрагивать N39 production | Детерминированный срез движения, валидация seed и снапшота; короткий smoke, без фактического Godot runtime в агентской среде | CODE_UNVERIFIED — [PR #130](https://github.com/Mefits/Living-Sector/pull/130), interactive-chat; Godot headless pending |
| N41 | **P0/P9: аудит происхождения ассетов native/observer:** инвентаризация, лицензии, безопасные ограничения переноса, воспроизводимый read-only checker | Все обнаруженные статические медиа учтены, неизвестные права не объявлены разрешёнными; без копирования ассетов | CODE_UNVERIFIED — PR #129, overnight-scheduler |

> **N42 START — 2026-11-12 14:11 MSK:** atomic claim `claims/N42.json` @ `387fed97cd6efeccf0421444b85db86e0844e602`, owner `second-chat-overnight`, **IN_PROGRESS**. Scope: read-only deterministic cross-domain integrity auditor, explicit provenance, headless regressions; branch `feature/godot-n42-world-invariant-audit-20261112`, based on integration #128 @ `1e4a1e9`.

> **N42 FINISH — 2026-11-12:** [Draft PR #131](https://github.com/Mefits/Living-Sector/pull/131) read-only closed-transfer audit of money, commodity stores/holds and ship ownership/docking, deterministic errors and headless test. **CODE_UNVERIFIED** (Godot not run). Integration #128 remains unchanged; P0 3/9, P1 0/9, P2 0/11, total 3/100 VERIFIED. Next N43 only after fresh claim check; N39/N40 untouched.

| N43 | **P1/P3: авторитетный resolver позиций native location** — world-space координаты орбит/планет/навигационных точек для транспортной модели N40 без карты, route-distance или вымышленных координат; N39 production не затрагивать | Детерминированное изменение положения при тиках, fail-closed неизвестных/неоднозначных location, headless smoke + PR | CODE_UNVERIFIED — [PR #133](https://github.com/Mefits/Living-Sector/pull/133), stacked on N40; runtime pending |

| N44 | **P6 research prerequisite gate (read-only):** audit Rust progression and deterministic evaluation of actual requirements without granting technology/resources; avoid N39/N43 overlap | Rust-sourced requirements, fail-closed evaluator, headless regression; no invented tech unlock | CODE_UNVERIFIED — [PR #132](https://github.com/Mefits/Living-Sector/pull/132), second-chat-overnight |

| N45 | **P6: funded research command bridge:** Rust research cost, N44 prerequisites, real ledger payment and idempotent order receipt; no invented unlock | Deterministic fail-closed paid order, duplicate/insufficient funds/save smoke | CODE_UNVERIFIED — [PR #134](https://github.com/Mefits/Living-Sector/pull/134), second-chat-overnight; N44 dependency |

| N46 | **P3: Rust-source fleet initialization:** реальный запуск стартовых кораблей из seed в корабельную модель без придуманного топлива/груза, безопасное подключение N40/N43 | Сверка Rust spawn/defaults, детерминированная bootstrap-модель, headless smoke/отказы, без пересечения N39 | CODE_UNVERIFIED — [PR #136](https://github.com/Mefits/Living-Sector/pull/136), interactive-chat; native Rust seeder verified statically, Godot runtime pending |

| N47 | **P1: fail-closed native seed validation:** deterministic schema/identity/referential checks before world bootstrap; no world mutation; independent of N39/N46 | Source parity, invalid fixture rejection, short Godot smoke | CODE_UNVERIFIED — [PR #135](https://github.com/Mefits/Living-Sector/pull/135), overnight-scheduler |

| N48 | **P2/P3: migration transport admission:** source-backed migration passenger capacity/location and replay-safe boarding admission, no teleportation or fabricated ship state | Fail-closed request validation, deterministic manifest, headless smoke; independent of N39 | CODE_UNVERIFIED — [PR #137](https://github.com/Mefits/Living-Sector/pull/137), second-chat-overnight |

| N49 | **P7/P1: read-only orbital selection diagnostics** — stable identity and selection snapshot, fail-closed invalid IDs, deterministic smoke; do not mutate P1 world | No new economy/AI claims; based on current integration #128; Godot headless pending | CODE_UNVERIFIED — [PR #138](https://github.com/Mefits/Living-Sector/pull/138), second-chat-overnight |

| N50 | N46 seed → Rust-native стартовые параметры экипажа, роли, мораль/усталость/голод/здоровье; без N39 | source-based crew initialization, snapshot/refusal, headless smoke | IN_PROGRESS — interactive-chat (ACTIVE); [claim N50](nightshift/claims/N50.json) |
| N51 | Детерминированный Rust ShipFitting: размер/слоты/эффекты стартового fitting; без фальшивых бонусов | 6 классов, comms_t2, size baseline, fitting parity | IN_PROGRESS — interactive-chat (QUEUED); [claim N51](nightshift/claims/N51.json) |
| N52 | Стартовые 24 ship credits через источник Rust и ledger-idempotency, без дублирования кошельков N39 | read-only provenance, deterministic funding admission, no double mint | IN_PROGRESS — interactive-chat (QUEUED); [claim N52](nightshift/claims/N52.json) |
| N53 | Докование/местонахождение стартового флота с реальной docking capacity и ID модулей из Rust | dock admission, ownership, overcapacity fail-closed, deterministic smoke | IN_PROGRESS — interactive-chat (QUEUED); [claim N53](nightshift/claims/N53.json) |
| N54 | Атомарный fleet+world save bridge для N40/N43/N46; не восстанавливать неполный P1 snapshot | strict schema, checksum provenance, no user save collision, tamper smoke | IN_PROGRESS — interactive-chat (QUEUED); [claim N54](nightshift/claims/N54.json) |

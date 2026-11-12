# Living Sector — журнал прогресса переноса Rust → Godot

> **Это главный живой чек-лист.** После каждого PR обновляем строки, дату и доказательство, а не только текст сообщения в чате.
> Исходники эталона: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`. План: [MIGRATION_ROADMAP_RU.md](MIGRATION_ROADMAP_RU.md). Полная карта 793 источников: [SOURCE_INVENTORY.json](SOURCE_INVENTORY.json).

**Внимание:** `VERIFIED` допустим только при наличии доказательства. `CODE_UNVERIFIED` значит скрипты написаны, но Godot не запускался. `DEFERRED_PRESERVED` — сохранено для будущего, не удалено. `TODO` — не начато. Игровой перенос пока **0 функциональных задач с подтверждённым Godot runtime**.

## Общий статус — 12 ноября 2026 (начат P0 перенос, блок 1)

| Этап | Проверено / всего | Текущее состояние |
|---|---:|---|
| P0 · Аудит и запускаемый каркас | 3/9 | 3 проверены по архиву/JSON, 4 написаны без запуска Godot, 1 ревизия в работе, 1 не начата |
| P1 · Модель мира, тики, сохранения | 0/9 | 3 задачи с кодом без запуска Godot, 5 частичных (включая только орбитный checkpoint), 1 ещё не начата; экономического тика нет |
| P2 · Экономика, население, производство | 0/11 | ожидает переноса |
| P3 · Корабли, логистика, договоры | 0/12 | ожидает переноса |
| P4 · Стройки, станции и колонии | 0/9 | ожидает переноса |
| P5 · Автономный ИИ | 0/11 | ожидает переноса |
| P6 · Игрок, исследования и развитие | 0/9 | ожидает переноса |
| P7 · Карта и UI | 0/10 | ожидает переноса |
| P8 · Приёмка Godot и эксплуатация | 0/9 | ожидает переноса |
| P9 · Сверка скрытых и альтернативных подсистем | 0/6 | ожидает переноса |
| P10 · Отдельный будущий дизайн, не паритет | 0/5 | 5 отложено; ожидает переноса |

**Статистика:** по умолчанию считаем только статус `VERIFIED` с evidence. Нельзя увеличивать процент за один лишь написанный файл; P10 — отдельный будущий дизайн, не обязательная часть паритета.

## Подробные задачи

Порядок идентификаторов неизменяем; новые задачи получают новый ID. В столбце «Источник» указан краткий относительный путь под `native/crates/sim_core/src/`, если явно не указан иной префикс.

### P0 — Аудит и запускаемый каркас

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P0-01` | Зафиксировать неизменный эталон Rust → `archive 6e40615` | `archive/rust-galaxy-067-reference` | `VERIFIED` | **Ветка есть, SHA зафиксирован**; [эталон](https://github.com/Mefits/Living-Sector/tree/archive/rust-galaxy-067-reference) |
| `P0-02` | Перечислить все файлы эталона и хеши → `SOURCE_INVENTORY.json` | `весь git tree Rust` | `VERIFIED` | **793 файла; Git tree не обрезан**; [эталон](https://github.com/Mefits/Living-Sector/tree/archive/rust-galaxy-067-reference) |
| `P0-03` | Разобрать 91 уникальный и 41 отличающийся файл корневого crates → `матрица решений по уникальному поведению` | `crates/ ↔ native/crates/` | `IN_REVIEW` | Ни одна уникальная механика не исчезла; **Обновление 12.11:** [132 несовпадающих файла сопоставлены по SHA](ROOT_TREE_DELTA_RU.md); смысловой разбор и лицензии ещё в работе |
| `P0-04` | Открыть Godot-проект/сцену → `Godot Editor` | `godot/project.godot` | `CODE_UNVERIFIED` | F5 без ошибок, Windows-снимок/лог; [код P0](https://github.com/Mefits/Living-Sector/pull/84) |
| `P0-05` | Загрузить 8 систем / 3 фракции из JSON → `scripts/native_data.gd` | `native/priv/galaxy/data/` | `CODE_UNVERIFIED` | Реальные JSON 8/3, без изменения ID; [код P0](https://github.com/Mefits/Living-Sector/pull/84); **Обновление 12.11:** [Строгий импорт 8/3 + аудит seed JSON](P0_SEED_AUDIT.json); реальный Godot запуск не проведён |
| `P0-06` | Выбор и обзор звёздной системы → `scenes/main.tscn; system_map.gd` | `native worlds/*.json` | `CODE_UNVERIFIED` | Клик, реальные тела/координаты; [код P0](https://github.com/Mefits/Living-Sector/pull/84); **Обновление 12.11:** [Карта: выбор, панорамирование, масштабирование, исходные объекты](https://github.com/Mefits/Living-Sector/tree/feature/godot-p0-world-inspector-and-audit/godot/scripts); не проверено в Godot |
| `P0-07` | Сравнить старые наборы миров, ресурсы и настройки → `versioned import policy` | `native/priv/data; genesis; galaxy; priv/` | `VERIFIED` | Нет случайного смешения стартов; **Обновление 12.11:** [4 набора миров разведены, 8/3/47/15/24 по данным](WORLD_SOURCE_POLICY_RU.md), [хеши](P0_SEED_AUDIT.json). Проверка исходников, не Godot runtime |
| `P0-08` | Проверить ассеты и лицензии → `asset licensing log` | `crates/client_bevy/assets; native/observer` | `TODO` | Нет неразрешённого переноса медиа/шрифтов |
| `P0-09` | Подготовить обновление проекта одной кнопкой → `UPDATE_AND_PLAY.cmd` | `GitHub; Godot source tree` | `CODE_UNVERIFIED` | Обновить/запустить без Rust и платного Actions; **Обновление 12.11:** [UPDATE_AND_PLAY.cmd](../UPDATE_AND_PLAY.cmd) + [SAVE_DIAGNOSTICS.cmd](../SAVE_DIAGNOSTICS.cmd); Windows-запуск не подтверждён |

### P1 — Модель мира, тики, сохранения

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P1-01` | Каталог типизированных ID и сущностей → `sim/entities` | `agents/*; world/registry.rs` | `IN_REVIEW` | Идентичность объектов стабильна; **Обновление 12.11:** [Read-only каталоги ID](../scripts/sim/world_model.gd) заложены; полные типы игровых сущностей не перенесены |
| `P1-02` | Данные орбит, координат, систем и маршрутов → `sim/world` | `world/*; agents/celestial_body.rs` | `IN_REVIEW` | Координаты и маршруты из родного JSON; **Обновление 12.11:** В модель перенесены исходные offsets и таблицы маршрутов; орбиты/переходы не исполняются; **Блок P1-A:** Нативный алгоритм обновления угла 47 тел перенесён в `world_model.gd`; переходы кораблей и орбиты станций ещё нет; [подробности](P1_NATIVE_TIME_AND_SAVE_RU.md) |
| `P1-03` | Единая SimWorld без графического состояния → `sim/world_model` | `sim_core/lib.rs; AgentStore` | `CODE_UNVERIFIED` | UI не владеет складами/казной; **Обновление 12.11:** Слой world_model.gd вне SceneTree реализован, но экономическое состояние и тики не подключены; **Блок P1-A:** Одна writable модель под `TickRunner`, UI читает копии; пока не связана с реальными экономическими системами; [подробности](P1_NATIVE_TIME_AND_SAVE_RU.md) |
| `P1-04` | Порядок фаз и очередь команд → `sim/tick_runner` | `sim_server/engine.rs; engine/apply.rs` | `IN_REVIEW` | Команды применяются один раз в верном порядке; **Блок P1-A:** `tick_runner.gd` выполняет очередь пауза/шаг/скорость и настоящую фазу bodies; остальные 19+ native-фаз сохранены в порядке, но не исполняются; [подробности](P1_NATIVE_TIME_AND_SAVE_RU.md); **ПЕРЕСМОТР АРХИТЕКТУРЫ:** [гибридный календарь и события](P1_TIME_ARCHITECTURE_REVIEW_RU.md), текущие 8 TPS — временный паритет, не окончательный выбор |
| `P1-05` | Фиксированные тики, пауза, ×1–×16 → `sim/clock` | `simulation/config.rs; engine.rs` | `CODE_UNVERIFIED` | FPS не меняет экономический тик; **Блок P1-A:** `clock.gd`: Rust TPS 8 и world_speed 0.25, pause/step/×16; Godot runtime ещё не проверен; [подробности](P1_NATIVE_TIME_AND_SAVE_RU.md); **ПЕРЕСМОТР АРХИТЕКТУРЫ:** [гибридный календарь и события](P1_TIME_ARCHITECTURE_REVIEW_RU.md), текущие 8 TPS — временный паритет, не окончательный выбор; **N2:** [нативный календарь](https://github.com/Mefits/Living-Sector/blob/feature/godot-nightshift-n2-calendar-second-20261112/godot/docs/N2_CALENDAR_HANDOFF_RU.md) и smoke-тест написаны без запуска Godot; единица «час» не назначена |
| `P1-06` | Инициализация мира из данных Galaxy → `sim/world_loader` | `sim_db/seeder.rs; spawner.rs` | `IN_REVIEW` | 8 систем/3 фракции/проверенные ID; **Обновление 12.11:** Строгий импорт замороженного мира с ID; настоящий игровой SimWorld ещё не создан |
| `P1-07` | Снимки состояния, события, дебаг → `sim/snapshots; debug` | `sim_protocol; snapshot.rs` | `TODO` | Статистика не выдумывается |
| `P1-08` | Первое Godot сохранение/загрузка → `sim/saves` | `sim_db/persistence.rs` | `IN_REVIEW` | После load тот же тик, состояние и деньги; **Блок P1-A:** `save_state.gd`: versioned FileAccess save/load только тика, clock, управления и углов; экономические счета ещё невозможно сохранять; [подробности](P1_NATIVE_TIME_AND_SAVE_RU.md) |
| `P1-09` | Тест неизменности чистого мира → `tests/world_parity` | `native/tests; rust test fixtures` | `CODE_UNVERIFIED` | Короткий сценарий без движения ресурсов; **Блок P1-A:** `tests/p1_tick_save_check.gd`: 8 ручных шагов, точный угол Earth, неизменность рынка/кораблей, проверка seed, FileAccess save/load; тест не запускался; [подробности](P1_NATIVE_TIME_AND_SAVE_RU.md) |

### P2 — Экономика, население, производство

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P2-01` | Полный список товаров, tier, базовые цены → `sim/economy/commodities` | `economy/commodities.rs` | `CODE_UNVERIFIED` | Каждый slug/ID/уровень совпадает |
| `P2-02` | Рецепты и побочные продукты → `sim/economy/recipes` | `economy/recipes.rs` | `CODE_UNVERIFIED` | Одна партия точно списывает все входы |
| `P2-03` | Рынок, спрос, предложение, лимиты складов → `sim/economy/markets` | `agents/market.rs; facility/restock.rs` | `TODO` | Нет скрытого создания/отрицательных запасов |
| `P2-04` | Ценообразование, срочность, спред → `sim/economy/pricing` | `economy/price_engine.rs` | `TODO` | Одинаковые входы дают сопоставимую цену |
| `P2-05` | Ордербук, сделки и деньги → `sim/economy/ledger` | `economy/order_book.rs; money.rs` | `TODO` | Покупатель и продавец платят/получают один раз |
| `P2-06` | Предприятия: циклы и состояние → `sim/production/facilities` | `agents/facility/*` | `TODO` | Производится только при нужных входах/условиях |
| `P2-07` | Работники, занятость, зарплаты и доступность → `sim/production/workforce` | `facility/workforce.rs; construction/labor.rs` | `TODO` | Нет выпуска без рабочих и реальных затрат |
| `P2-08` | Население, еда/вода, благосостояние → `sim/population` | `agents/population.rs` | `TODO` | Потребление и изменения населения не фиктивны |
| `P2-09` | Износ, ремонт, прекращение работы и банкротство → `sim/production/maintenance` | `facility/mod.rs; agents/faction.rs` | `TODO` | Остановки и источники денег видимы |
| `P2-10` | Два типа модулей предприятий T1–T3 → `sim/production/fitting` | `facility_modules/mod.rs; module_production.rs` | `TODO` | Множители работают только при настоящем модуле |
| `P2-11` | Налог/трансферты/субсидии и баланс → `sim/factions/treasury` | `agents/faction.rs; relief.rs` | `TODO` | Баланс денег/эскроу не удваивается |

### P3 — Корабли, логистика, договоры

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P3-01` | Классы, параметры и компактное хранилище кораблей → `sim/ships/state` | `ship/components.rs; modules/mod.rs` | `CODE_UNVERIFIED` | [N13 PR #95](https://github.com/Mefits/Living-Sector/pull/95): 6 Rust classes, size tiers, validated cargo/fuel, atomic snapshot; Godot headless pending |
| `P3-02` | Физическое движение и межсистемные коридоры → `sim/logistics/travel` | `world/travel.rs; pathfinder.rs; ship/mod.rs` | `TODO` | Груз прибывает только после перелёта |
| `P3-03` | Топливо, докинг, обслуживание, состояние → `sim/ships/operations` | `ship/mod.rs; ship/actions.rs` | `TODO` | Реальные расходы и ограничения |
| `P3-04` | Вместимость трюма, погрузка и разгрузка → `sim/logistics/cargo` | `ship/transactions.rs; contracts.rs` | `TODO` | Нельзя взять > вместимости |
| `P3-05` | Торговый ИИ, память цен и BT → `sim/ships/ai` | `ship/behavior.rs; ai/*` | `TODO` | Автономные рейсы физически выполняются |
| `P3-06` | Добывающие и исследовательские роли → `sim/ships/mining_explore` | `ship/behavior.rs; agents/celestial_body.rs` | `TODO` | Ресурс и исследование привязаны к действию |
| `P3-07` | Все виды контрактов и статусы → `sim/economy/contracts` | `economy/contracts.rs; missions.rs` | `TODO` | Posting → accepted → cargo → delivered → paid |
| `P3-08` | Эскроу, возврат, продление, истечение, возраст → `sim/economy/funding` | `contracts.rs; engine/contract_funding.rs` | `TODO` | Нет двойной оплаты/замороженных денег |
| `P3-09` | Репутация, союзники и запрет врагов → `sim/factions/relations` | `faction_relations.rs; economy/reputation.rs` | `TODO` | Пираты не торгуют как союзники |
| `P3-10` | Экипаж, голод/усталость/мораль/зарплаты → `sim/ships/crew` | `ship/components.rs; ship/mod.rs` | `TODO` | Поведение следует состоянию экипажа |
| `P3-11` | Пять слотов кораблей, модульные улучшения T1–T3 → `sim/ships/fitting` | `modules/mod.rs; module_production.rs` | `TODO` | Точно те же эффекты модулей |
| `P3-12` | Сейв во время полёта и незавершённого договора → `sim/saves/ship_resume` | `sim_db/persistence.rs; 015_ship_resume_state.sql` | `TODO` | Без дублирования контракта/груза |

### P4 — Стройки, станции и колонии

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P4-01` | Цепочка физической постройки → `sim/construction` | `agents/construction/*; strategy/construction.rs` | `TODO` | Материалы, деньги и труд подтверждены |
| `P4-02` | Склад стройки и трудовые смены → `sim/construction/labor` | `construction/labor.rs; engine/transactions.rs` | `TODO` | Каждый шаг требует реального ресурса |
| `P4-03` | Уровни станции T1=4, T2=5, T3=6 → `sim/stations/tier_slots` | `strategy/progression.rs` | `TODO` | Слот не возникает от графики |
| `P4-04` | Верфи, корпуса и закупка модулей → `sim/shipyard` | `agents/facility/mod.rs; module_production.rs` | `TODO` | Корпус/модуль произведён/оплачен |
| `P4-05` | Орбитальное движение станции и местоположение → `sim/stations/orbits` | `agents/celestial_body.rs; facility/components.rs` | `TODO` | Инспектор привязан к станции |
| `P4-06` | Пассажиры, миграция и реальные перевозки → `sim/population/migration` | `contracts.rs; strategy/colony_development.rs` | `TODO` | Население не телепортируется |
| `P4-07` | Колонизация: выбор, стройка, переселение → `sim/colony` | `strategy/colony.rs; colony_development.rs` | `TODO` | Новая колония только после исполнения |
| `P4-08` | Конкуренция за площадку, отмены и восстановление → `sim/colony/claims` | `colony.rs; construction/executor.rs` | `TODO` | Не появляются две колонии на одном месте |
| `P4-09` | Обслуживание и остановки после строительства → `sim/stations/maintenance` | `agents/facility; production_chain.rs` | `TODO` | Построенное предприятие действительно работает |

### P5 — Автономный ИИ

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P5-01` | Личности и общая utility-оценка Главы → `sim/strategy/director` | `ai/personality.rs; strategy/director.rs` | `TODO` | Разные черты дают объяснимые предпочтения |
| `P5-02` | Аварийные приоритеты еды/воды → `sim/strategy/crisis` | `strategy/director.rs; options.rs` | `TODO` | Выживание вытесняет необязательное |
| `P5-03` | Оценка нескольких реальных альтернатив → `sim/strategy/options` | `strategy/options.rs; sourcing.rs` | `TODO` | Причина/оценка из того же выбора |
| `P5-04` | Администратор: работники и модули → `sim/strategy/station_admin` | `strategy/station.rs` | `TODO` | Назначение исполняется локально |
| `P5-05` | Администратор: договоры/постройки → `sim/strategy/admin_orders` | `strategy/construction.rs; orders.rs` | `TODO` | Глава не управляет каждым кораблём |
| `P5-06` | Нативные HTN/GOAP/Beam адаптеры сохранены → `sim/strategy/planning` | `strategy/planning/*` | `TODO` | Изучены все альтернативные пути, без fake steps |
| `P5-07` | Память выбранной цели и переключение → `sim/strategy/memory` | `strategy/director.rs; long_term.rs` | `TODO` | Цель переживает исследование и кризис |
| `P5-08` | Обнаружение тупиков, откат и восстановление → `sim/strategy/replanning` | `strategy/planning/ledger.rs; native_execution.rs` | `TODO` | Незавершённый реальный контракт не теряется |
| `P5-09` | Производственная причинная цепочка → `sim/strategy/production_chain` | `strategy/production_chain.rs; dependencies.rs` | `TODO` | Одна физическая квитанция на результат |
| `P5-10` | Самостоятельный цикл закрытия дефицита → `tests/autonomy_cycle` | `strategy.rs; engine.rs` | `TODO` | Фракция сама доставляет и уменьшает дефицит |
| `P5-11` | Отдельное наблюдение за выбором планировщика → `debug/ai_decisions` | `strategy/planning/hybrid.rs; comparisons` | `TODO` | В прогнозе нет выдуманных потерь/прибылей |

### P6 — Игрок, исследования и развитие

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P6-01` | Мандаты Delegated / Advise / Hold → `sim/policies/mandates` | `strategy/governance.rs; economic_mandate.rs` | `TODO` | Hold не финансирует приказ |
| `P6-02` | Уставы, приоритеты, бюджет и одобрение → `sim/policies/charter` | `strategy/charter.rs; economic_proposal.rs` | `TODO` | Превышение бюджета блокируется |
| `P6-03` | ID оплаченного контракта у решения игрока → `sim/policies/receipts` | `strategy/economic_proposal.rs` | `TODO` | Мандат не оплачивает чужое действие |
| `P6-04` | Дерево существующих исследований и ворот → `sim/research/tech` | `strategy/director.rs; progression.rs` | `TODO` | Нет доступа до выполнения условий |
| `P6-05` | Физическая научная смена → `sim/research/work` | `strategy/coordination.rs; engine.rs` | `TODO` | Вычитаются материалы/зарплата |
| `P6-06` | Реальные T1–T3 улучшения зданий → `sim/research/station_upgrades` | `strategy/progression.rs` | `TODO` | Улучшение требует ресурса и труда |
| `P6-07` | Корабельные и станционные T2/T3 исследования → `sim/research/equipment` | `modules; facility_modules; recipes` | `TODO` | Рецепты соответствуют открытию |
| `P6-08` | Сохранить проектные невыполненные tech-гейты → `design_backlog` | `strategy/progression.rs; native/reference` | `TODO` | Невыполненное не объявлено активным |
| `P6-09` | Три режима пользователя: наблюдать/управлять/сравнивать → `scenes/player_modes` | `Observer; user design notes` | `TODO` | Переход режима не портит мир |

### P7 — Карта и UI

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P7-01` | 2D звёздная карта, масштаб и камера → `scenes/map` | `observer/map-primitives.js; client_bevy/camera` | `TODO` | Выбор/следование/масштаб |
| `P7-02` | Схематичные глобусы и образы планет → `scenes/planet` | `native worlds JSON; visual reference` | `TODO` | Не перепутаны игровые типы/ресурсы |
| `P7-03` | Схематичные корабли и станции Yiotro/Shapez → `scenes/ships_stations` | `observer assets; client_bevy render` | `TODO` | Силуэты различимы и последовательны |
| `P7-04` | Лёгкая пакетная отрисовка многих объектов → `scripts/view/batching` | `client_bevy render; spatial/*` | `TODO` | Объекты данных не превращены в тысячи узлов |
| `P7-05` | Инспектор кораблей, экипажа, контракта → `scenes/ship_inspector` | `observer/native.html; client_bevy/ui/ship*` | `TODO` | Состояние из реальной модели |
| `P7-06` | Инспектор станций: склады, рабочие, процессы → `scenes/station_inspector` | `observer/strategy-ui.js; telemetry-ui.js` | `TODO` | Есть шкалы и реальные причины простоя |
| `P7-07` | Управление Главой, исследования и история → `scenes/governance` | `observer/governance*.html; galaxy.html` | `TODO` | Намерения отделены от исполнения |
| `P7-08` | Инспекторы рынка, колоний и событий → `scenes/markets_colonies` | `observer/model.js; client_bevy/ui/*` | `TODO` | Не потеряны оригинальные окна |
| `P7-09` | Модульный стиль и ассеты без лиценз. проблем → `themes/assets` | `client_bevy/assets; observer/assets` | `TODO` | Право использования подтверждено |
| `P7-10` | Скорость ×16, пауза, окна, фокус объекта → `scenes/controls` | `observer/app.js; runtime.rs` | `TODO` | Контролы реально меняют тик/камеру |

### P8 — Приёмка Godot и эксплуатация

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P8-01` | Версионирование сохранений и безопасный рестарт → `sim/saves/schema` | `sim_db migrations 001-018; snapshot.rs` | `TODO` | Живое сохранение рестартует без потерь |
| `P8-02` | Возможность импортировать старую SQLite → `tools/legacy_importer` | `sim_db/migrations; persistence.rs` | `TODO` | Без изменения старого файла |
| `P8-03` | Контроль денег/складов/контрактов по квитанциям → `tests/ledger` | `money.rs; contracts.rs; native fixtures` | `TODO` | Ноль двойных оплат |
| `P8-04` | Сопоставление 3–5 коротких Rust/Godot сценариев → `tests/parity` | `native/tests; strategy fixtures` | `TODO` | Одинаковые входы, объяснимые различия |
| `P8-05` | Бюджет производительности и реальный ×16 → `tests/performance` | `simulation/lod.rs; spatial/*` | `TODO` | FPS и тики не смешиваются |
| `P8-06` | Локальное обновление GitHub + запуск Godot → `UPDATE_AND_PLAY.cmd` | `GitHub; source ZIP` | `TODO` | Один клик, без компиляции Rust |
| `P8-07` | Диагностика кнопкой в ZIP и тик-лог → `SAVE_DIAGNOSTICS.cmd` | `native/reports; Observer telemetry` | `TODO` | Отчёт отправляется без паролей/сейвов |
| `P8-08` | Windows экспорт, portable проверка → `dist/Godot Windows` | `Godot exporter; old Windows reference` | `TODO` | Играбельный standalone с данными |
| `P8-09` | Сводка известных отличий и решение о замене Rust → `MIGRATION_SIGNOFF.md` | `весь реестр + пользовательская приёмка` | `TODO` | Ни одна критическая механика не забыта |

### P9 — Сверка скрытых и альтернативных подсистем

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P9-01` | Сравнить отличающиеся исходники root и native → `coverage decisions` | `root crates vs native/crates` | `TODO` | 41 diff рассмотрен |
| `P9-02` | Аудио, иконки, визуальные шейдеры и лицензии → `visual asset manifest` | `root client_bevy assets` | `TODO` | 91 уникальный файл разобран |
| `P9-03` | Учесть все старые карты и референсы → `legacy reference ledger` | `priv/; native/priv/genesis; docs` | `TODO` | Старое не смешано с основным миром |
| `P9-04` | Сопоставить root client_bevy UI и Web Observer → `UI feature completeness matrix` | `client_bevy/ui; native/observer` | `TODO` | Нет потерянных возможностей просмотра |
| `P9-05` | Не забыть редкие механики и тест-стенды → `deferred feature list` | `native/reference; examples; tests; ai` | `TODO` | Для каждой найден источник и статус |
| `P9-06` | Закрыть все 793 записи inventory решением → `порт/ссылка/осознанный отказ` | `SOURCE_INVENTORY.json` | `TODO` | Ноль безымянных исключений |

### P10 — Отдельный будущий дизайн, не паритет

| ID | Переносимый результат | Источник | Статус | Мини-критерий / доказательство |
|---|---|---|---|---|
| `P10-01` | 1000-летняя нелинейная прогрессия → `design/future_tech` | `старые дизайн-доки; деревья` | `DEFERRED_PRESERVED` | Не привязывать к году |
| `P10-02` | T4 Сфера Дайсона и военные мегаструктуры → `design/megastructures` | `референсы / пожелания` | `DEFERRED_PRESERVED` | Не объявлять готовым |
| `P10-03` | Стратегическая война и дипломатия → `design/war_diplomacy` | `личности + прошлые планы` | `DEFERRED_PRESERVED` | Не подменять ИИ войны агрессивностью |
| `P10-04` | Планетарное развитие и глобусы с объектами → `design/planet_view` | `выбранная визуальная концепция` | `DEFERRED_PRESERVED` | Без девяти жёстких слотов |
| `P10-05` | Новые режимы игры и интерактивная 4X → `design/interactive_4x` | `наблюдатель/управление/сравнение` | `DEFERRED_PRESERVED` | Не тормозить старый функционал |

## Как фиксировать одну итерацию

1. Берём **3–5 взаимосвязанных TODO-задач** и создаём ветку с явным диапазоном ID, например `feature/godot-p2-01-04`.
2. После написания кода ставим `CODE_UNVERIFIED`. После запуска Godot и короткой приёмки — `VERIFIED` + ссылка на PR/коммит/небольшой `RESULT.json` или диагностический ZIP.
3. Если перенесена только часть: пишем в доказательстве **что осталось**, а статус оставляем `CODE_UNVERIFIED` или `IN_REVIEW`. Не закрываем строку авансом.
4. Если механика в старом Rust непригодна или дублирует новую: `DEFERRED_PRESERVED` + ссылка на старый код и явное решение в PR. **Нельзя удалять запись.**
5. Перед завершением фазы проверяем её Gate в [плане](MIGRATION_ROADMAP_RU.md). Параллельный UI разрешён, но не заменяет проверку логики.

## Сигналы риска, требующие отдельной задачи

- Сравнение корневой `crates/` и `native/crates/`: 91 уникальный файл + 41 отличающийся — нельзя считать автоматически избыточным.
- `resource_grades.json` имеет `active: false` — не включать систему в Godot по умолчанию лишь из-за существующего файла.
- `progression.rs` содержит как реальные правила, так и проектные цепочки — различать executable vs design-only.
- Не переносить сотни кораблей как сотни высокозатратных деревьев Nodes; модель данных отдельно.
- Два режима старого Rust/запуска, разные наборы миров и старые SQLite не должны молча смешиваться.
- HTTP 404 в экспериментальной Rust при проверке экономического поручения — известный недоказанный сценарий. Отслеживать, но не блокировать Godot-каркас.

## Инженерное решение по инструментам — 12 ноября 2026

**Исследование Godot и сторонних компонентов проведено, но прогресс игровых задач НЕ изменён.**

- [Сопоставление P0–P10 с встроенными средствами и библиотеками](GODOT_TOOLING_DECISIONS_RU.md)
- [Постоянная база геймдев-приёмов](GAMEDEV_KNOWLEDGE_BASE_RU.md)
- [Убираем jitter: интерполяция между реальными снимками](SMOOTH_MOTION_RU.md)

Внедрение плагинов: **0**. Проверенные на Godot runtime сторонние зависимости: **0**. Выбранное направление: сначала встроенные средства; GUT первым кандидатом после проверки версии, остальные — по нужде и бенчмарку. Не закрываем P0/P1 и не меняем сохранённые числа только за документацию.

## Подтверждённое исследование архитектуры времени — 12.11.2026

- [Аудит Factorio/RimWorld/Victoria 3/Stellaris и upstream SpaceProjectSim](INDUSTRY_TICK_ARCHITECTURE_RU.md).
- Решение на этом этапе: **сохранить единый дискретный тик**, использовать разные cadence и события внутри него; **8 TPS/×0.25 остаются временным эталоном**, а не навсегда утверждённой настройкой.
- Это архитектурное исследование без выполнения Godot runtime-тестов и без реализации новых механик. Статусы задач **не повышены**: P0 3/9, P1 0/9, общий 3/100 подтверждённых.


## N1 — статический аудит P0/P1-A (12.11.2026)

**CODE_UNVERIFIED, PR #90.** Усилены границы native Galaxy seed и P1 WorldModel: конечные `orbit_period > 0` и `0 <= current_angle < 360`, форма вложенных данных до публикации изменяемого состояния, одинаковая валидация live/persisted `pause`/`resume`. Добавлен `p1_audit_check.gd` и третий шаг `RUN-P1-SMOKE.cmd`. Статически подтверждены 8 JSON / 47 тел; Godot runtime не запускался. Это исправление качества P0/P1, не основание повышать VERIFIED-числа: **P0 3/9, P1 0/9, P2 0/11, общее 3/100 VERIFIED**.

### Ночная итерация N3 — 12.11.2026 (PR #91)

- `CODE_UNVERIFIED`: отдельные `godot/scripts/sim/event_queue.gd`, `cadence.gd`, интеграция в `tick_runner.gd`, тест `godot/tests/n3_events_check.gd`.
- Сохранены порядок фаз Rust, deterministic event ordering, запрет дубликатов и повторного исполнения, атомарное восстановление очереди. Пока события только уведомляют, без выдуманной экономики.
- PR: https://github.com/Mefits/Living-Sector/pull/91 (база N2 PR #89); статическая проверка скобок четырёх файлов, Godot не запускался.
- Подтверждённые числа неизменны: **P0 3/9, P1 0/9, P2 0/11, всего 3/100**. Новая задача с кодом без Godot Runtime: **1 (N3)**; совокупное число смотреть по детальным строкам трекера.


### Nightshift N4 — code ready, Godot not yet verified (2026-11-12)

[PR #92](https://github.com/Mefits/Living-Sector/pull/92): native Galaxy 0.6.7 entity registry and directed travel route graph; 8 systems, 47 bodies, 15 facilities, 24 ships, 3 markets, 3 populations, 9 nav sites, 12 directed edges. Native ship/nav site/population missing IDs are represented with clearly labeled seed-local ordinal keys; no fabricated native IDs. Deterministic shortest path and headless acceptance script. **CODE_UNVERIFIED**; Godot Runtime not executed. This is preparatory code for P1/P3 and does not add VERIFIED checklist items. No production, ship movement or market logic claimed.

**N5 / PR #93 (12.11.2026):** 17 Rust commodities + 14 recipes and fractional transform committed, short headless test added; no Godot runtime verification. P2 remains **0/11 VERIFIED**; N6/N9 still need real production/storage/permissions. [PR #93](https://github.com/Mefits/Living-Sector/pull/93).

### N11 — credit ledger boundary, PR #94 (12.11.2026)

**CODE_UNVERIFIED, not a complete P2-05/P2-07/P2-11.** Atomic native-wallet debit/credit transfers with receipt idempotence, escrow reserve/refund primitive and snapshot/restore in `godot/scripts/sim/economy/credit_ledger.gd`; short `n11_ledger_check.gd`. Rust `economy/money.rs` is an accounting view, not a second ledger; native wallet ownership and payroll/market/contract integration still TODO. [Draft PR #94](https://github.com/Mefits/Living-Sector/pull/94), [handoff](nightshift/N11_LEDGER_HANDOFF_RU.md). Godot runtime absent, smoke not executed. VERIFIED unchanged: **P0 3/9, P1 0/9, P2 0/11, total 3/100**.

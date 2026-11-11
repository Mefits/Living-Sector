# Living Sector → Godot: исследование штатных механизмов и готовых библиотек

**Дата:** 12.11.2026. **Ориентир:** [Roadmap P0–P10](MIGRATION_ROADMAP_RU.md), [живой трекер 100 задач](MIGRATION_TRACKER_RU.md), [замороженный Rust](https://github.com/Mefits/Living-Sector/tree/archive/rust-galaxy-067-reference).

## Архитектурное решение: разделение модели и визуализации

Симуляция **логически отделена от SceneTree и графических нод Godot, но исполняется в том же процессе**. Не запускаем второй сервер и не создаём параллельную экономику. Истинные запасы, деньги, ID, контракты и состояние ИИ содержатся в одной модели мира. Godot Control/CanvasItem отображает проекцию модели, а UI-команды проходят через очередь и исполняются один раз. Это позволяет отделить TPS от FPS, запускать headless-тесты и рисовать много кораблей пакетно.

### Матрица инструментов по этапам

| Этап | Прежде всего встроенные возможности | Сторонние кандидаты | Решение |
|---|---|---|---|
| **P0** импорт и карта | JSON, FileAccess, DirAccess, CanvasItem._draw, Control, Theme | Не требуется | **Встроено.** Не переписывать JSON-парсер или собственный UI-движок. Оставляем 8/3 исходных JSON. |
| **P1** чистая модель и тики | RefCounted, Resource для каталогов, Engine, SceneTree, signals, fixed-step, typed containers | Пока не требуется | **Встроено + собственный узкий симуляционный TickRunner.** Не создавать Nodes по числу агентов, не связывать экономический тик с FPS. |
| **P1/P8** сохранения | FileAccess + JSON либо store_var/get_var, ResourceSaver, версия схемы | [Godot SQLite](https://github.com/2shady4u/godot-sqlite) только для импортера старой SQLite | **Встроено для новых сейвов.** Plugin не нужен на старте. Старые 18 миграций требуют отдельного чтения в безопасную новую схему. |
| **P2** экономика, рынки, рецепты | Resource каталоги + тестируемая логика, signals, встроенные математические функции | Не требуется | **Перенос по Rust.** Готовой библиотеки с нашими контрактами, квитанциями, эскроу и формулами нет. Плагин экономики не должен менять поведение. |
| **P2/P7** шкалы и графики | ProgressBar, TextureProgressBar, Tree, Control._draw | [TauPlot](https://github.com/ze2j/tau-plot) — кандидат для сложных графиков | **Шкалы штатные.** TauPlot pure GDScript с графиками, но 0.2.0 помечен unstable; только после отдельного мини-теста. |
| **P3** маршруты | AStar2D, в случае потребности Dijkstra, Curve2D только для визуализации | Не нужен чужой pathfinding для первых систем | **Встроено**, но стоимости рёбер берём из native travel_routes.distance, не из длины нарисованной линии. При неточной эвристике A* используем нулевую эвристику / Dijkstra. |
| **P3** множество кораблей | CanvasItem._draw, MultiMeshInstance2D, при необходимости RenderingServer | Не нужен графический плагин | **Высокий приоритет встроенного.** Группировать по системам/типам. MultiMesh не делает индивидуальный culling; тестировать FPS и memory. |
| **P3/P5** состояния кораблей и BT | Скриптовые структуры, signals, данные планов | [LimboAI](https://github.com/limbonaut/limboai), [Godot State Charts](https://github.com/derkork/godot-statecharts) | **Только испытание на небольшой выборке.** BT/FSM не заменяют наш GOAP/HTN/Beam, Director, ledger; scene-tree на каждый из тысяч кораблей может быть дорого. Не добавлять оба фреймворка вместе. |
| **P3/P7** плавное движение | Physics Interpolation, Engine.get_physics_interpolation_fraction, Camera2D, Transform2D | Не нужен jitter-fixer plugin | **Использовать встроенное**, но при независимом сим-тик-цикле и пакетной отрисовке адаптировать presenter. [Пояснение](SMOOTH_MOTION_RU.md). |
| **P4** строительство и станции | ProgressBar, Tween, AnimationPlayer, Timer и signals | Не требуется | **Встроено для отображения.** Физическая стройка/материалы/зарплаты — портировать из Rust. Анимация не может завершить стройку сама. |
| **P5** ИИ Глав/администраторов | Resource/RefCounted, чистый AI policy API, snapshot, scenario tests | LimboAI, State Charts — только для локального исполнения/визуального debug | **Собственный смысловой планировщик из существующего Rust**, без чужого «готового 4X AI». |
| **P6** большое дерево технологий и зависимости | [GraphEdit + GraphNode + GraphFrame](https://docs.godotengine.org/en/stable/classes/class_graphedit.html), Resources | Не требуется на старте | **Штатный графовый редактор.** Даёт масштаб, связи, авторасстановку и взаимодействие. Условия исследований проверяет SimWorld, GraphEdit сам ничего не разблокирует. |
| **P6/P7** интерфейс фракции | Control, Containers, Tree, TabContainer, ScrollContainer, Theme, RichTextLabel | Не нужен второй UI-фреймворк | **Встроено.** Политики Hold/Advise/Delegate — проверяемые команды, не визуальные эффекты кнопок. |
| **P7** камера, закрепление за объектом | Camera2D, position smoothing, Tween | [Phantom Camera](https://phantom-camera.dev/overview/what-is-this) | **Сначала Camera2D.** Phantom Camera кандидат для следования/переключения целей/мультикамерных сцен, лицензия MIT; проверить точную совместимость до установки. |
| **P7** планеты-глобусы и станции | Polygon2D, CanvasItem, ShaderMaterial, Gradient, FastNoiseLite | Не обязательно | **Встроено.** Схематичные глобусы/модули, без вымышленных слотов/добычи от шейдера. |
| **P8** локальные тесты и экспорт | Debugger/Profiler, headless CLI, export templates, лог-файлы | [GUT](https://github.com/bitwes/Gut) или [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) | **Сначала GUT, после успешного P0 запуска.** Для Godot 4.7 нужен совместимый GUT 9.7.x; не устанавливать оба одновременно. Тесты и диагностика на ПК, без платных Actions. |
| **P9** исходники Bevy и аудио/иконки | Godot assets importer, AudioStreamPlayer, ShaderMaterial | Плагины необязательны | **Разбирать смысл и лицензии 132 исходных отличий**, не переносить автоматически шрифты/музыку/WGSL. |
| **P10** T4, длинная прогрессия | GraphEdit, Resource/Conditions, фильтры/virtualized UI | Позже по измерениям | **Уже есть готовые базовые инструменты.** Не считать дизайн 1000 лет реализованной механикой. |

## Четыре действительно полезных готовых дополнения

1. **[GUT](https://github.com/bitwes/Gut)** — GDScript unit tests, CLI, mock/stub, отчёты. **Первый кандидат для внедрения** после реального старта Godot, заметно упрощает проверку экономических формул и очередей. MIT. Таблица совместимости версий — в официальном README.
2. **[LimboAI](https://github.com/limbonaut/limboai)** — behavior trees + state machines и визуальный debugger. Поддерживает GDScript-задачи, но ядро C++ и дистрибуция GDExtension; 1.8.x заявлен для Godot 4.6+ в GDExtension и отдельного модуля для 4.7. **Не ставить массово на корабли до бенчмарка 100/1000/10000 агентов**.
3. **[Phantom Camera](https://phantom-camera.dev/)** — камера по целям, плавный переход/следование, кадрирование нескольких целей; кандидат когда встроенной Camera2D окажется мало. Не нужен просто для zoom и pan.
4. **[TauPlot](https://github.com/ze2j/tau-plot)** — графики в GDScript: линия, столбцы, scatter, потоковая телеметрия. **Исследовательский кандидат**: beta/нестабильный API, возможен риск несовместимости; бар-склады и прогресс рисуем штатными контролами.

Другие: [Godot State Charts](https://github.com/derkork/godot-statecharts) — альтернативная FSM, не обязательна вместе с LimboAI; [Godot SQLite](https://github.com/2shady4u/godot-sqlite) — готовые native-библиотеки, приоритет лишь если реально решим импортировать старые SQLite; [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) — достойная альтернатива GUT, но **одна тестовая система на проект**.

**Версия:** зафиксировать **Godot 4.7 stable** для следующей приёмки (4.8 beta3 на 09.11.2026 — не использовать как стабильную базу). Старое поле проекта с фичей 4.3 — минимальная совместимость каркаса, не рекомендация ставить устаревший Godot.

## Правила предотвращения костылей

Перед реализацией каждой подсистемы обязательно:
1. Назвать задачу Pn-xx и проверить в документации Godot, **нет ли встроенной функции**.
2. Если есть сторонний плагин, проверить upstream, **лицензию**, точный release и версию Godot, Windows/Linux export, platform-specific precompiled GDExtension, обновления, безопасность editor plugin.
3. На отдельной маленькой сцене проверить plugin и сравнить с **прошитым инструментом Godot**; не менять экономическую механику ради лёгкого интеграционного API.
4. Проверить нагрузку и число одновременно обновляемых объектов, особенно для десятков тысяч кораблей/сотен технологий.
5. Фиксировать версию/commit стороннего плагина только после проверки. Если инструмент не подошёл, записать почему, **не тащить зависимость в игру**.
6. В трекере отражать только фактический код/тест. **Каталог не означает, что что-либо уже установлено или прошло тесты**.

## Источники

- [Official Godot: scene/data Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Official Godot: plugin installation](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html)
- [Official Godot: GraphEdit](https://docs.godotengine.org/en/stable/classes/class_graphedit.html)
- [Official Godot: physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html)
- [Official Godot: MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Official Godot: save games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
- [Official Godot: CLI/export](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
- [Official Godot: Release Policy](https://docs.godotengine.org/en/stable/about/release_policy.html)

**Статус на 12.11.2026:** выбор решений исследован и задокументирован. Плагины **не установлены**; совместимость не проверена на Godot Runtime; Rust-паритет не изменён.

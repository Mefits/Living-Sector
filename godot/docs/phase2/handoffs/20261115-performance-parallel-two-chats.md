# Living Sector — параллельные исправления производительности, 2 чата

Статус: **ПОДГОТОВЛЕНО, РАЗРАБОТКА ЕЩЁ НЕ НАЧАТА**. Координация: этот документ, открытые PR и tldraw → вкладка **«Оптимизация»**:
https://www.tldraw.com/f/Dzo-huxLVMxka2COuru0w?d=v171.20.2123.1315.o5cZqK2hvNs6Y-gsoTmdH

Репозиторий: https://github.com/Mefits/Living-Sector
Интеграционная ветка (НЕ редактировать напрямую): `integration/godot-phase2-unified-20261113`.
Проверенный код до подготовки: `2915ba07e1f17f86e63f21c904288a9b70c11423` (PR #256).
Обе рабочие ветки создаются от **одного docs-only координационного коммита** поверх этого SHA.

## Почему разделение безопасно

| Исполнитель | Задача из аудита Астры | Собственные файлы | Чужие / общие файлы, не менять |
| --- | --- | --- | --- |
| Чат №1 (A) | **II-A.2.2 / II-B** — N39 локальные валидаторы, read/write versions, измерения целостности | `godot/scripts/sim/phase1/n39_native_world_production.gd`, `godot/scripts/sim/phase1/n39_native_world_schema.gd`, новый `n39_*validator*.gd`, только `godot/tests/p2_parallel_a_*.gd`, `godot/docs/phase2/handoffs/*parallel-a*.md` | N153 dispatch, N4 route graph, N9 ledger, N158, UI, общая CI-конфигурация |
| Чат №2 (B) | **II-C** — N153 индексы пригодных кораблей и активных контрактов, детерминированность выбора | `godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd`, новые `n153_*index*.gd` в phase2, только `godot/tests/p2_parallel_b_*.gd`, `godot/docs/phase2/handoffs/*parallel-b*.md` | N39 production/schema, N9 ledger, N4 route_graph, N158, UI, общая CI-конфигурация |

Обе работы выполняются независимо от PR #249 (исторический интеграционный PR). Права на общий тест или общий `.github/workflows/p2-unified-godot-smoke.yml` **не выданы ни одному чату**. Для CI можно добавлять **отдельный** workflow в своей ветке (`p2-parallel-a-*.yml` или `p2-parallel-b-*.yml`) и запускать его один раз после подготовки тестов; или попросить координатора запустить совместный интеграционный smoke после merge. Никакой общей ветки в период параллельной работы.

### Зафиксированные ветки

- **A**: `feature/perf-parallel-a-n39-validators-20261115`
- **B**: `feature/perf-parallel-b-n153-indices-20261115`
- Оба PR направлять **в `integration/godot-phase2-unified-20261113`**, сначала **Draft**.
- Не сливать PR самостоятельно. Два PR объединяет **один координатор** последовательно; второй проверяется заново против обновлённого HEAD. Это предотвращает гонку с PR #249 и незамеченное изменение общих инвариантов.
- Перед любой правкой перечитывать HEAD собственной ветки, `git diff`/изменённые пути второго исполнителя и эту таблицу. Если требуется чужой файл: **поставить BLOCKED, описать интерфейс/требование и дождаться координатора**, а не редактировать чужое.

## A — рамка готового макроблока

Опираться на исходный раздел tldraw **II-A.2 / II-B; P1 WORLD/SCHEMA/ACCOUNTS**. Текущий N39 уже имеет `Ledger.fork()`, COW N9, ship-domain COW и изолированные записи рынков/N21 (PR #250/#251/#253/#255/#256). Старое полное `Schema.validate` пока обязательно для всех публикаций.

1. Измерить реальные вызовы/время `Schema.validate`, `Schema.accounts` и World копий по callsite/фазам на том же оригинальном seed. **Не начинать с отключения проверки**.
2. Выделить безопасный узкий путь (N150 markets или N21 ship/dock) с явным read-set/write-set/preconditions, локальным валидатором затронутых строк и типизированными версиями/поколениями. Не добавлять новые игровое состояние или вторую финансовую власть, если версии можно хранить runtime-only.
3. Сопоставить локальный валидатор с полным `Schema.validate` как oracle на успешных/искажённых предложениях. **Не делать кэш "validated=true" по mutable Dictionary без гарантированной invalidation**. Не менять причину отказа, финансовый commit, тексты сохранений, BT, RNG, очереди, cargo/доки/контракты.
4. Если рискованно убирать runtime full oracle — оставить его включённым, принять только доказанную часть (например, профилирование, реестр dirty sets, read-only projection) и назвать II-A.2.2 частично выполненным. Не заявлять FPS без whole-sim A/B.

### A — строгая приемка

- Godot 4.7.2: parser, `p2_n39_owned_market_dock_write_set_check.gd`, `p2_n21_ledger_history_guard_check.gd`, `p2_n9_append_only_journal_check.gd`, `p2_n9_owned_fork_history_check.gd`, `p2_n39_ship_domain_copy_boundary_check.gd`.
- Реальные 420 тиков + N38 restart на тике 360; затем 900 тиков с сохранением N129 на 825-м, если 420 прошли.
- Отрицательные сценарии: invalid prices, forged market owner/identity, old N9 receipt edit/removal, duplicate dock receipt and queue overcapacity, proposal alias mutation, missing/unmatched account. Исходные причины отказа сохраняются.
- **Одинаковые** world/ledger/contract/ship/BT/cargo/clock поля на контрольных снимках (не ограничиваться одними числами summary). A/B old/new на одном CI runner; предоставить время симуляции, p95 по окнам при наличии профиля, и стоимость валидации.
- Никаких изменений SEARCH_BUDGET, расписания тиков, денег и экономических формул.

## B — рамка готового макроблока

Опираться на tldraw **P2 N153 CONTRACTS И ROUTES; II-C / II-D ИНДЕКСЫ**. PR #254 уже добавил ограниченный кэш кратчайших путей в `route_graph.gd` — повторно НЕ реализовывать Dijkstra/route cache.

1. Измерить работу `unified_n153_contract_dispatch.gd::propose()`: scans `contracts.keys().sort()`, `ships.keys().sort()`, число пар и долю отказов. Определить, какие дешёвые **неизменяемые для одного вызова** поля можно индексировать, чтобы не выполнять всю дорогую `_ready_ship()` и N153.select_contract на заведомо неготовых парах.
2. Реализовать source-compatible deterministic candidate index/rosters, сохранив исходный порядок **contract ID → ship ID**, tie-break `profit >`, `already_assigned`, `blocked` и точные `ship_rejection_counts` (если пропуск пары меняет эти числа — он недопустим).
3. Каждую пригодность по fuel/cargo/knowledge/reputation/market/permissions/funding **перепроверять в текущем мире** непосредственно перед выбором. Для индекса между тиками требовать строгие версии/сброс на контрактах, кораблях, ценах, N38 reload; проще/безопаснее сначала index на один `propose` вызов.
4. Тесты `p2_n153_live_contract_dispatch_check.gd` и `p2_n153_route_cache_parity_check.gd` + новые `p2_parallel_b_*.gd` на противоположные directed paths, равные profits, занятый ship, expired/posting, no-funds/stock/cargo/fuel, пирратов, порядок и blocked reasons. Никаких выдуманных движений, доходов или оплаченных контрактов.
5. Реальный 420-тактный accept с restart360, 900 после успешного 420; paired old/new; отдельно большой **правильно валидный тестовый fixture** 24/100/500 ships и contracts с настоящими IDs/funds/route permissions. **Не отождествлять synthetic microbenchmark с улучшением всей игры**.

### B — запреты

Нельзя менять `n39_native_world_production.gd`, `n39_native_world_schema.gd`, `credit_ledger.gd`, `n158_production_runtime.gd`, `route_graph.gd` или `p2-unified-godot-smoke.yml`. Если их интерфейсы нужны — оформить запрос в собственном handoff, совместить потом. Запрещено сокращать `SEARCH_BUDGET`, менять деньги/AI/tie-break/порядок контрактов или делать вид, что корабли уже летают.

## Общая приемка и связь

1. Прямо в PR/коммите сначала указать **исходный базовый SHA** и список занятных файлов. На tldraw рядом со своим блоком поставить **оранжевый** «В РАБОТЕ», ссылки на свою ветку/PR и измерения.
2. Работать **крупным блоком**, не дробить на десятки PR. Допускается несколько коммитов внутри одного PR.
3. Сначала локальные / целевые тесты, затем **один** большой CI-проход. GitHub Actions экономить. 420+N38 restart360 обязателен, 900 — после успешного 420. Не выдавать один PASS за доказательство 10 000 тиков.
4. В отчёте каждого PR: exact baseline SHA, список touched files, проверенные и непроверенные инварианты, реальные failing/blocked причины, численное A/B и ссылки на логи, какие еще остались риски.
5. **Зелёный заголовок ставит только интегратор после PASS, ревью и merge**. Отрицательный результат, эксперимент без выигрыша, незакрытый пункт — оранжевый/серый с пояснением.
6. Если один PR смержен раньше, второй нельзя мержить «на старых зелёных»; перепроверить diff относительно свежего `integration` и прогнать минимум объединённый smoke. Если оба менять один файл всё же потребовалось — объявить конфликт до начала.
7. Периодические отчёты писать в собственные handoff-файлы, сохраняя видимость для второго чата. Координатор проверяет PR и раздел «Оптимизация».

Этот документ — **протокол разделения работы**, не свидетельство о запуске или выполнении исправлений.

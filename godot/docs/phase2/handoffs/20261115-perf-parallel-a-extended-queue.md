# Living Sector Performance — Chat A | 8-block execution backlog

**СТАТУС: ЧАСТИЧНО ВЫПОЛНЕНО, CI 420/900 PASS, ОРАНЖЕВЫЙ ДО REVIEW/MERGE.** Подробности: [implementation handoff](./20261115-perf-parallel-a-implementation.md). Текущий PR: https://github.com/Mefits/Living-Sector/pull/257 (Draft), ветка `feature/perf-parallel-a-n39-validators-20261115`.

Координация: https://github.com/Mefits/Living-Sector/blob/integration/godot-phase2-unified-20261113/godot/docs/phase2/handoffs/20261115-performance-parallel-two-chats.md

Tldraw: https://www.tldraw.com/f/Dzo-huxLVMxka2COuru0w — вкладка **«Оптимизация»**, только дорожка чата №1.

Базовый исходник до ветвления: `2915ba07e1f17f86e63f21c904288a9b70c11423`; общий docs-only HEAD при резервировании `823f32379b10bfefae5a5cebb1c0c0e622509f72`. Перед началом проверить актуальные SHA и чужой lease.

## Таблица прогресса (обновлять после каждого крупного блока)

| ID | Статус | Коммит / тест | Решение |
| --- | --- | --- | --- |
| A1 | DONE | `063e4d6`, CI #43728402372 | 47 Schema.validate, 46 accounts, 34 World clones; top costs/p95 измерены. |
| A2 | DONE-TESTED (targeted) | `9976c91`, `134b0b6`, CI #43732867924 | Формальные read/write sets N150/N21, отсутствие alias; N9/Schema immutable preconditions и source paid fixture PASS. |
| A3 | DONE (N150 scope) | `a6a71f5`, `703084f` | 6 observation fields, identity/prices/crisis flags, full Schema oracle включён. |
| A4 | DONE-TESTED (targeted) | `2bf8ecd`, `a7a900e`, `63f02df`, `134b0b6`, CI #43732867924 | Strict shadow + new paid N9 provenance, duplicate ID, fractional fee, FIFO, capacity, original refusal reason; 900 pending. |
| A5 | DONE-TESTED (N150/N21 scopes) | `ba9f106`, `9503806`, `06d3195`, `63f02df`, CI #43732867924 | Opt-in generation preconditions, failed-commit unchanged, signed N38 reload namespaces; old callers unchanged. |
| A6 | DONE (N150 narrow) | `9bf2b97`, CI #43728402372 | Без deep-copy на равных N150 observation fields; 420 A/B 99,640→96,069 ms. |
| A7 | DONE-TESTED (fixtures) | `9f20cab`, `d3c7e8d`, `134b0b6`, CI #43732867924 | Schema-valid 24/100/500 ship-wallet worlds, source N21 paid, over-capacity, N38 full bytes, canonical alias isolation; new 420/900 A/B pending. |
| A8 | IN_PROGRESS (previously PASS) | CI #43728402372 SUCCESS; new CI #43732867924 underway | Existing 420/900/ N38 PASS; expanded N21/scale suite targeted PASS; new whole-sim A/B + 900 pending. |

### A1 — baseline и профилирование N39 (обязательный первый блок)
Определить вызовы `Schema.validate`, `Schema.accounts`, `world_snapshot`, `duplicate(true)` по фазам, на каких тик-кейсах они вызываются и кто владеет предложением. Добавить opt-in телеметрию только в собственной зоне. Измерить p50/p95/p99, количество validator calls и World copies при одинаковом seed; проверить, какие операции действительно часто исполняются. **Выход:** таблица callsites, ссылки на конкретные исходники, точный baseline SHA, измеренные горячие пути и приоритет. Нет ускорения без измерений.

### A2 — точная область записи для рынка и dock-коммита
Выписать read-set/write-set/preconditions по `apply_market_phase`, `_commit_native_n21`, смежным N39 производственным стадиям без изменения их результатов. Отдельно проверить arrays/dictionaries, которые могут изменяться через ссылки. Добавить негативные тесты external mutation, stale proposal и конфликта store. Не переписывать Ledger: у N9 собственный authoritative commit.

### A3 — shadow market validator
Новый локальный market validator: ID владельца, допустимые поля, цены/спрос/history/stock правила, товары, типы и конечные числовые значения. Сравнивать результат на реальном N150 stage со старым **полным `Schema.validate`**. Данные за пределами write-set должны оставаться неизменяемыми. Оставить oracle включённым до доказанного паритета на всех реально поддерживаемых исходных случаях. Проверять неизменность reason для негативных случаев.

### A4 — shadow dock validator и N21 денежные доказательства
Проверить корабль, занятие дока, queue FIFO, facility credits, dock_receipts, полное состояние N9 и старые receipts. Локальный валидатор не может разрешить то, что Schema/N9 ранее запрещали. Проверить duplicate dock receipt, два корабля на один док, дробная плата/недостаток денег, отказ между reserve и commit, внешнюю подмену nested data. Никаких fake cargo/money и ослабления N9.

### A5 — write-version и precondition регистр
Добавить deterministic runtime-only поколения (или иной строгий механизм stale-proposal prevention), без нарушения N38 roundtrip и без второго authority. Доказать сброс/восстановление после restart360. Отдельно проверить propose-from-old-version и failed-commit does not advance. Не использовать кеш валидности mutable Dictionary без полного invalidation.

### A6 — измеренное снятие дублирования проверок
Только после A1–A5 попробовать убрать повторную работу, если она действительно проявилась. Сохранять строгий `Schema.validate` при runtime commit, пока negative/full-state oracle parity не доказывает безопасную замену. Если ускорение ограниченного пути отсутствует, оставить обоснованные проверочные границы или откатить эксперимент, а не принимать «оптимизацию» по числу изменённых строк.

### A7 — parity и нагрузочные fixtures
Создать целевые тесты `godot/tests/p2_parallel_a_*.gd`: source-world, многочисленные wallets/ship docks/stations, paid receipt index, correct ownership, full cargo/contract/BT/RNG/state snapshots. Проверять весь `var_to_bytes`/stable canonical representation, а не только краткие counters. Исключить ложные перемещения и изменения баланса. Для 100/500 агентов масштабировать корректные сущности и сопровождающие бюджеты, а не дублировать JSON корабля.

### A8 — интегрированная проверка, решение и очередь дальше
После локальных тестов один связанный CI-прогон: Godot 4.7.2 parser; 420 ticks N38 restart360; затем 900 ticks (tick825 N129); real paid fixtures; A/B old/new на том же runner, p95 если профилирование доступно. Вывести actual changed files/commit IDs, fallback/rejected experiments и оставшиеся риски, 10k без доказательства не объявлять «готовым». Обновить собственный handoff и PR #257. При успешном завершении **не останавливаться на первом зелёном тесте**, переходить к следующему недоделанному пункту; если все A1–A8 выполнены — заключительное N39 ревью, никакой самовольной работы в зоне B.

## Область владения и контроль параллельности

**Можно менять** `godot/scripts/sim/phase1/n39_native_world_production.gd`, `godot/scripts/sim/phase1/n39_native_world_schema.gd`, новые helper-модули `n39_*validator*.gd`, только тесты `godot/tests/p2_parallel_a_*.gd`, этот файл и собственные handoff `*parallel-a*.md`. Свой отдельный CI workflow допускается, но избегать частых запусков.

**Нельзя менять** `unified_n153_contract_dispatch.gd`, `route_graph.gd`, `credit_ledger.gd`, `n158_production_runtime.gd`, `main.gd`, station admin, `event_queue.gd`, общий `p2-unified-godot-smoke.yml`, тесты/документы чата B. Если нужен соседний API — отметить BLOCKED и перейти к следующему независимому пункту.

**Петля продолжения:** прочитать эту очередь, lease, свежие SHA и PR B → выбрать первый TODO → сделать код + тесты + собственный commit → обновить таблицу статусов → немедленно взять следующий безопасный пункт в пределах активной итерации. Сообщение пользователя «Продолжай» без новых ограничений означает вернуться к первому незакрытому пункту. Сам PR не сливать, карточку до интеграции держать оранжевой. Если тесты опровергают эффект — сделать REJECTED с причиной, откатить рисковые правки и перейти к следующему независимому пункту.

**Финишный критерий:** очередь рассмотрена полностью или остался конкретный BLOCKED с требованиями внешней интеграции; не создавать бессмысленные изменения ради «занятости». Проверенный зелёный заголовок публикует только координатор после merge.

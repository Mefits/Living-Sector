# Living Sector · PERF Parallel A / N39 · handoff 2026-11-15

Статус: **A1–A8 DONE-TESTED, ОРАНЖЕВЫЙ ДО REVIEW/MERGE КООРДИНАТОРОМ**. Только PR #257; самим не объединять.

- Репозиторий: https://github.com/Mefits/Living-Sector
- Ветка: `feature/perf-parallel-a-n39-validators-20261115`
- PR: https://github.com/Mefits/Living-Sector/pull/257 (Draft)
- База резервирования: `823f32379b10bfefae5a5cebb1c0c0e622509f72` (shared coordination docs commit)
- Одобренный runtime перед этой работой: `2915ba07e1f17f86e63f21c904288a9b70c11423`.
- Чат B: `feature/perf-parallel-b-n153-indices-20261115`, отдельная зона; пересечений runtime-файлов нет.

## Выполненные блоки

- **A1 — измерительная инфраструктура:** отмечены 47 прямых вызовов `Schema.validate`, 46 `Schema.accounts`, 28 глубоких + 6 поверхностных копий `_world`; wrap per-callsite только для сбора времени. Актуальная `native_schema_profile()` при `LS_PROFILE_NATIVE_PHASES=1` показывает calls/total/max/min/p50/p95/p99 и отдельные поля копий; эти значения не сериализуются и не влияют на игровое решение. Первый профиль 900 тиков: 6243 копии World за ~38,68 с; в финальном CI 6243 / 33,67 с. Единый аппаратный baseline для сравнения не переносить между разными runs.
- **A2/A3 — N150 ownership и локальный validator:** новый `n39_market_observation_validator.gd` отвергает неверное количество рынков, ID, отсутствующие шесть observation dictionaries, отрицательные/нечисловые цены, неверные crisis_notified flags; полный `Schema.validate` по-прежнему проверяет весь World до каждого удачного publish.
- **A5 — завершённые N150/N21 поколения:** runtime-only `market_observation_version()` и `n21_write_version()`; опциональные `expected_version` и `expected_n21_version` отклоняют stale предложения. После N38 restore оба owner выдают отрицательный диапазон поколений; схема World/ledger/N38 не меняется, старые вызывающие APIs остаются совместимыми.
- **A6 — реальная локальная оптимизация:** `apply_market_phase` не делает `duplicate(true)` для **неизменённых** вложенных observation dictionaries; меняющиеся значения по-прежнему глубоко копируются до публикации. Окончательный scoped N150+N21 код даёт 80,326→77,990 с (−2,91%) в **последнем одном paired A/B**; предыдущая пара 99,640→96,069 с была на иной версии и не должна смешиваться с финальной.
- **A7 DONE-TESTED:** 9 целевых тестов включают `p2_parallel_a_market_version_validator_check.gd`, N21 источник реального платёжного transfer fee=50, forged paid receipt/fee/fifo/stale denial, exact N9 ledger receipts, переполненные доки, isolated Schema-valid 24/100/500 ship-wallet fixtures, полный N38 `var_to_bytes` parity, отсутствие алиасов. Synthetic fixtures не означают полноценную игровую экономику на 500 кораблях.

## A2/A4/A5 — read/write границы (новый пакет N39)

| Операция | Читать / original preconditions | Единственный write-set | Дополнительная защита |
| --- | --- | --- | --- |
| `apply_market_phase` N150 | `_last_tick`, размер и идентичность рынка, шесть observation Dictionary, конечные неотрицательные prices, original `Schema.validate` | `markets[location].{prices,demand,seed_demand,consumption_window,orders,history}`; физический `supply`, деньги, facility/ship untouched | `expected_version` опционален; stale reject до staging; изменённые dictionaries `duplicate(true)`; одинаковые поля используют canonical owned reference |
| `_commit_native_n21` | canonical World domains, old receipts N21/N9, `Ledger.restore`, `Ledger.total`, all old N9 receipts via `retains_receipts`, `Schema.validate`, exact `Schema.accounts` | Только `ships`, `facilities`, `dock_receipts` плюс единая атомарная публикация N9; **не изменять** N153/UI/contracts/BT/cargo policy | `expected_n21_version` опционален; source-legal transitions test shadow; новый paid dock receipt теперь дополнительно обязан иметь точный immutable N9 transfer |
| `restore` N38 | Полная существующая Schema, journals, time cursors и original N38 ABI | existing `_world` / `_ledger`; поколения только runtime-only, вне save | N150/N21 после restore получают отрицательный namespace, чтобы предложенный до N38 positive-token не мог совпасть |

В N21 `dock_queue` — упорядоченная **очередь ожидания**, а `docked_at` — единственный признак занятого слота: `queue.size()` не считается occupancy. Локальный validator отклоняет `dock_capacity_exceeded`, повторный FIFO waiter, fractional fee, missing N9 payment, изменённые legs/kind/tick. Старое правило owner-коммита сначала сохраняет все прежние refusal reasons; новый `n21_local_...` появляется только на ранее незащищённом платёжном provenance после полного oracle. При `LS_PROFILE_NATIVE_PHASES=1` дополнительно измеряется `n21_shadow_false_rejections`, приемка требует ноль.

**Новые коммиты и target checks:** `2bf8ecd` (N21 local oracle), `ba9f106` (N21 generations + shadow), `a7a900e` (paid receipt gate), `63f02df` (stale/fractional/FIFO negatives), `9503806` (N38 N150 epochs), `06d3195` (market epoch negative), `9f20cab` + `d3c7e8d` (valid 24/100/500 and real occupancy), `134b0b6` (source N21 paid, N9 receipt, duplicate ID, alias), `de2c497` (dedicated CI). Nine targeted Godot 4.7.2 tests PASS in [CI #43732867924](https://github.com/Mefits/Living-Sector/actions/runs/43732867924); 420/900 A/B ещё выполнялся на момент записи.

## Godot 4.7.2 / CI

- Первый run: https://github.com/Mefits/Living-Sector/actions/runs/43727865302 — **FAIL parser**, случайная замена подстроки `physical_world.duplicate`/`before_world.duplicate`; исправлено в `340d156`. До simulation не дошёл.
- Второй run: https://github.com/Mefits/Living-Sector/actions/runs/43728191148 — **PASS** parser и шесть целевых тестов, но FAIL нового profiling test (повторная переменная `stats` в одном GDScript scope), исправлено `f832da6`. А/B не запускался.
- Третий run: https://github.com/Mefits/Living-Sector/actions/runs/43728402372 — **SUCCESS** Godot parser, шесть targeted tests, 420 тиков A/B + N38 restart360, все полные SHA256-контрольные снимки совпали. Исходник N39: 99,640 ms; новая версия N39: 96,069 ms, improvement ~3,58%, один paired run. 900 реальных тиков с N38 restart360 и N129 tick825: **PASS**. Profiling `LS_PROFILE_NATIVE_PHASES=1` включён только в 900-кандидате, поэтому не сравнивать его elapsed с nonprofiled A/B. Один `ubuntu-24.04` runner, один Godot 4.7.2, оригинальный seed, полные hashes `JSON.stringify(checkpoint).sha256_text()`, не только summary; baseline N39 берётся ровно из `823f323...`.
- Исходный полный `Schema.validate`, N9 journal, N38 save/restore, dispatch, route_graph, N158, ticks, money and balance не ослаблены/не менялись.

## Расширенная приёмка A4–A8 (15 ноября, CI)

[CI #43732867924](https://github.com/Mefits/Living-Sector/actions/runs/43732867924) **SUCCESS**:
- 9 целевых тестов Godot 4.7.2 PASS, включая `P2_PARALLEL_A_N21_SOURCE_PAID_PASS fee=50`, отказ forged N9 invoice/fractional fee/replay, версионирование после N38, полный 24/100/500 ship-wallet fixture.
- 420 тиков / N38 restart360: все полные SHA256 snapshots old/new совпали.
- 900 тиков / N38 restart360 / tick825 N129: PASS. N21 shadow checks после restore: **185**, false rejections **0**. `Schema.accounts` по инструментированным N39 callsites: **4715 вызовов / 0,540332 с** за участок после N38.
- A/B old/new **84,857 → 87,655 с (+3,30% медленнее)** на одном runner. Это показывает, что дополнительная проверка N21 в общем no-change пути могла съесть ранний выигрыш. Два отдельных runner-запуска (прежние 99,64→96,07 и новые 84,86→87,66) нельзя смешивать.

**A6 corrective change:** `8b722a9` исключает повторный проход `DockDeltaValidator` для обычных N21 стадий **без добавления новых `dock_receipts`**. Старый `Schema.validate` по-прежнему проверяет весь World; N9.restore, все старые receipt proof, account totals и новые paid-receipt proof при появлении квитанции остаются. Публикации/формулы/AI/баланс/схема N38 неизменны. Новый одинарный paired A/B + 900 gate запущен в [CI #43733851184](https://github.com/Mefits/Living-Sector/actions/runs/43733851184); численное ускорение после изменения **ещё не подтверждено**.

## A8 — окончательный код и приёмка (авторитетное состояние)

**Финальный код:** `8b722a948ffa65a0761177d0c187d5f31c93608d` для безопасного N21 conditional paid-proof; CI workflow commit `3ab75fd7732fcb0aef79eb623812e4156b994dcc`; последующие docs-only коммиты код не меняют.

[Godot 4.7.2 CI #43733851184](https://github.com/Mefits/Living-Sector/actions/runs/43733851184) — **SUCCESS**. Девять целевых тестов PASS; парный old/new A/B на **одном** Ubuntu 24.04 runner, 420 реальных тиков, **N38 restart360**: baseline **80 326 ms**, candidate **77 990 ms**, delta **−2,91%**, все полные SHA256 checkpoint summaries идентичны. Дополнительно candidate прошёл 900 реальных тиков с N38 restart360 и исходным N129 tick825, без создания фальшивых корабельных движений и экономических операций.

**Финальный профиль (post-restart, 900):**
- `copy:deep:L129` `world_snapshot` — **6243** calls, **33 670 557 μs**, p95 **14 484 μs**;
- `validate:L475` ship-phase — **787** calls, **4 284 207 μs**, p95 **6415 μs**;
- `Schema.accounts` (все instrumented N39 callsites) — **4715** calls, **508 850 μs**;
- N21 shadow: **185** checks, **0** false rejections. Точный N9 original paid transfer/fee=50 проверен новым focused test.

**Решение A6:** расширенный proof сначала вызвал +3,30% замедление (CI #43732867924). Исправление `8b722a9` выполняет **дополнительную** N21 проверку только если появилось новое `dock_receipts`; исходные full Schema, N9.restore, старые immutable receipt сравнения и account invariants всегда выполняются. Тесты доказывают сохранение отказов и N9 оплаты. Последний одинарный A/B подтвердил умеренное улучшение, но не гарантирует FPS после 10k тиков.

**Все блоки A1–A8 DONE-TESTED В РАМКАХ OWNED N39 FILES.** Применение/merge, интеграция двух PR и combined smoke — работа координатора. Только он может менять tldraw header на зелёный после подтверждённого merge. Наибольший расход `world_snapshot` требует согласованного read-only N158/UI API, не входит в lease A. Отдельный postmerge 10k tick профиль не проводился.

## Измеренные горячие места — 900 ticks / opt-in profile

Замеры относятся к **N39 owner callsites**, а не суммарной стоимости всей игры; повторные вызовы включены.

| Callsite оригинального N39 | Calls | Total, s | p95, ms | Диагноз |
| --- | ---: | ---: | ---: | --- |
| `copy:deep:L129`, `world_snapshot` | 6 243 | 38.677 | 17.583 | доминирующий read-only полный World copy |
| `validate:L475`, `apply_ship_phase` | 787 | 4.440 | 6.280 | многократная полная Schema в корабельной фазе |
| `copy:deep:L2008`, N39 stage | 540 | 4.051 | 10.536 | deep World stage |
| `copy:deep:L196`, lifecycle | 540 | 3.690 | 10.189 | deep World в maintenance lifecycle |
| `validate:L1168` | 540 | 3.165 | 6.836 | Schema на ship-owned World |
| `validate:L255` | 540 | 3.090 | 6.801 | lifecycle source oracle |
| `validate:L4121` | 540 | 3.087 | 6.605 | N150 market oracle |
| `validate:L995` | 540 | 2.968 | 6.157 | Schema на корабельном домене |
| `validate:L2079` | 540 | 2.958 | 6.204 | full schema в фазе производства |
| `validate:L3219` | 540 | 2.856 | 5.948 | full schema в research |
| `validate:L1049` | 540 | 2.816 | 5.935 | full schema в ship memory |
| `copy:deep:L3098` | 540 | 1.721 | 4.047 | research stage deep World |

`Schema.accounts`: расширенный CI измерил 4715 вызовов / 0,540332 с за post-N38 участок; дорогостоящие callsites остаются у полного Schema и глубоких World copies.

**Основное следующее ускорение требует контракта read-only snapshot на стороне вызывающего N158/UI, который запрещён к редактированию этой ветке.** Не использовать невалидируемый cache `World.duplicate(true)` по mutable Dictionary. Открыть отдельный интеграционный блок координатору.

**Строгая граница доказанного:** настоящий 900-tick PASS — не означает производительность после 10 000 тиков, 100/500 кораблей либо доказательство fps. Отрицательные проверки не покрыли все перечисленные в первоначальном координационном handoff случаи: queue overcapacity, повтор док-оплаты в одной стадии и mass fixtures — оставить A4/A7 частичными.

## Только наши изменённые файлы

`godot/scripts/sim/phase1/n39_native_world_production.gd`,
`godot/scripts/sim/phase1/n39_market_observation_validator.gd`,
`godot/tests/p2_parallel_a_market_version_validator_check.gd`,
`godot/tests/p2_parallel_a_checkpoint_fingerprint_check.gd`,
`.github/workflows/p2-parallel-a-n39-validator-proof.yml`,
`godot/docs/phase2/handoffs/*parallel-a*.md` (этот handoff), и ранее зарезервированный lease. Запрещённые файлы не затронуты.

## Координатору после этого PR

1. Проверить Diff PR #257, SHA исправления `8b722a9`, CI #43733851184 и ограничения N9/Schema/N38. Слить **только координатором**.
2. После последовательного merge PR #257/#258 провести **общий** smoke на обновлённом integration HEAD — отдельные зелёные CI на старых SHA не доказывают объединённую корректность.
3. Для следующего самостоятельного этапа отдельно закрепить владельца N158/UI read-only World projection: 6243 полных снимка World / 33,67 с в профиле 900; не вносить bypass без строгой инвалидации и тестов.
4. 10k тиков и FPS по реальному экрану не тестировались; 24/100/500 были валидными синтетическими данными только для load/alias/schema/ledger/dock prove. До merge tldraw остаётся оранжевым.

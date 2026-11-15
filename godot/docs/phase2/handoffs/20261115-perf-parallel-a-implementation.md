# Living Sector · PERF Parallel A / N39 · handoff 2026-11-15

Статус: **IN PROGRESS, ОРАНЖЕВЫЙ**. Только PR #257, НЕ объединять самостоятельно.

- Репозиторий: https://github.com/Mefits/Living-Sector
- Ветка: `feature/perf-parallel-a-n39-validators-20261115`
- PR: https://github.com/Mefits/Living-Sector/pull/257 (Draft)
- База резервирования: `823f32379b10bfefae5a5cebb1c0c0e622509f72` (shared coordination docs commit)
- Одобренный runtime перед этой работой: `2915ba07e1f17f86e63f21c904288a9b70c11423`.
- Чат B: `feature/perf-parallel-b-n153-indices-20261115`, отдельная зона; пересечений runtime-файлов нет.

## Выполненные блоки

- **A1 — измерительная инфраструктура:** отмечены 47 прямых вызовов `Schema.validate`, 46 `Schema.accounts`, 28 глубоких + 6 поверхностных копий `_world`; wrap per-callsite только для сбора времени. Актуальная `native_schema_profile()` при `LS_PROFILE_NATIVE_PHASES=1` показывает calls/total/max/min/p50/p95/p99 и отдельные поля копий; эти значения не сериализуются и не влияют на игровое решение. Профиль 900 тиков ниже; 6243 полных World snapshots дают ~38,68 с только в диагностике их копирования.
- **A2/A3 — N150 ownership и локальный validator:** новый `n39_market_observation_validator.gd` отвергает неверное количество рынков, ID, отсутствующие шесть observation dictionaries, отрицательные/нечисловые цены, неверные crisis_notified flags; полный `Schema.validate` по-прежнему проверяет весь World до каждого удачного publish.
- **A5 — ограниченное versioning:** runtime-only `market_observation_version()` и опциональный `apply_market_phase(tick, updates, expected_version=-1)` дают отклонение stale N150 observation proposal. Версия увеличивается только после успешной публикации; при восстановлении N38 новый экземпляр её инвалидирует (не является версией физического stock/ledger/доков).
- **A6 — реальная локальная оптимизация:** `apply_market_phase` не делает `duplicate(true)` для **неизменённых** вложенных observation dictionaries; меняющиеся значения по-прежнему глубоко копируются до публикации. Один paired A/B на одном runner подтвердил 99,640 → 96,069 с (~3,58% ускорения); это наблюдение, а не гарантированный FPS в 10k-tick режиме.
- **A7 частично:** новый тест `p2_parallel_a_market_version_validator_check.gd` доказывает цену -1, forged identity/owner oracle, stale generation, no proposal aliases, missing/extra N9 accounts, duplicate FIFO waiter. Пять исходных N39/N21/N9 тестов также прошли. Полные 100/500 actor fixtures и отдельные сценарии занятости дока НЕ завершены.

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

`Schema.accounts` точно инструментирован, но не входит в топ-12 по total в финальном профиле; суммарное численное значение всех account callsites текущий сокращённый лог не публикует. Нельзя заявлять долю без полного отчёта.

**Основное следующее ускорение требует контракта read-only snapshot на стороне вызывающего N158/UI, который запрещён к редактированию этой ветке.** Не использовать невалидируемый cache `World.duplicate(true)` по mutable Dictionary. Открыть отдельный интеграционный блок координатору.

**Строгая граница доказанного:** настоящий 900-tick PASS — не означает производительность после 10 000 тиков, 100/500 кораблей либо доказательство fps. Отрицательные проверки не покрыли все перечисленные в первоначальном координационном handoff случаи: queue overcapacity, повтор док-оплаты в одной стадии и mass fixtures — оставить A4/A7 частичными.

## Только наши изменённые файлы

`godot/scripts/sim/phase1/n39_native_world_production.gd`,
`godot/scripts/sim/phase1/n39_market_observation_validator.gd`,
`godot/tests/p2_parallel_a_market_version_validator_check.gd`,
`godot/tests/p2_parallel_a_checkpoint_fingerprint_check.gd`,
`.github/workflows/p2-parallel-a-n39-validator-proof.yml`,
`godot/docs/phase2/handoffs/*parallel-a*.md` (этот handoff), и ранее зарезервированный lease. Запрещённые файлы не затронуты.

## Следующая итерация

1. Доделать **A4** N21 dock bounded local proof / overcapacity and duplicate receipts, не трогая внешние N21/N9 файлы. Обязателен старый Schema oracle и проверка unchanged failure reason. Не путать очередь ожидающих с фактически занятыми доками.
2. Доделать **A7** строго валидные 100/500 actor fixtures и негативные alias/exact-reason cases; не клонировать корабли без корректных IDs/accounts и маршрутов.
3. **A8:** CI SUCCESS для real 420/900 + N38, один paired A/B; дополнить quantitative accounts rollup/более широкий нагрузочный замер только если полезно. Ускорение World snapshots требует координации с владельцем N158 — не править его здесь.
4. Tldraw: в собственном блоке заголовок уже стал «В РАБОТЕ», цвет оранжевый. Попытки обновить карточку позже вернули «That board is not open»; повторять, когда view доступен. Зеленеть карточку только после review и merge интегратором.

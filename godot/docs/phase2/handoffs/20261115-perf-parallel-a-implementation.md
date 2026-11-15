# Living Sector · PERF Parallel A / N39 · handoff 2026-11-15

Статус: **IN PROGRESS, ОРАНЖЕВЫЙ**. Только PR #257, НЕ объединять самостоятельно.

- Репозиторий: https://github.com/Mefits/Living-Sector
- Ветка: `feature/perf-parallel-a-n39-validators-20261115`
- PR: https://github.com/Mefits/Living-Sector/pull/257 (Draft)
- База резервирования: `823f32379b10bfefae5a5cebb1c0c0e622509f72` (shared coordination docs commit)
- Одобренный runtime перед этой работой: `2915ba07e1f17f86e63f21c904288a9b70c11423`.
- Чат B: `feature/perf-parallel-b-n153-indices-20261115`, отдельная зона; пересечений runtime-файлов нет.

## Выполненные блоки

- **A1 — измерительная инфраструктура:** отмечены 47 прямых вызовов `Schema.validate`, 46 `Schema.accounts`, 28 глубоких + 6 поверхностных копий `_world`; wrap per-callsite только для сбора времени. Актуальная `native_schema_profile()` при `LS_PROFILE_NATIVE_PHASES=1` показывает calls/total/max/min/p50/p95/p99 и отдельные поля копий; эти значения не сериализуются и не влияют на игровое решение. Точные горячие callsites: **ОЖИДАЮТСЯ профили 900 тиков**, не заявлять до результата.
- **A2/A3 — N150 ownership и локальный validator:** новый `n39_market_observation_validator.gd` отвергает неверное количество рынков, ID, отсутствующие шесть observation dictionaries, отрицательные/нечисловые цены, неверные crisis_notified flags; полный `Schema.validate` по-прежнему проверяет весь World до каждого удачного publish.
- **A5 — ограниченное versioning:** runtime-only `market_observation_version()` и опциональный `apply_market_phase(tick, updates, expected_version=-1)` дают отклонение stale N150 observation proposal. Версия увеличивается только после успешной публикации; при восстановлении N38 новый экземпляр её инвалидирует (не является версией физического stock/ledger/доков).
- **A6 — реальная локальная оптимизация:** `apply_market_phase` не делает `duplicate(true)` для **неизменённых** вложенных observation dictionaries; меняющиеся значения по-прежнему глубоко копируются до публикации. Это нельзя считать ускорением всей игры до A/B.
- **A7 частично:** новый тест `p2_parallel_a_market_version_validator_check.gd` доказывает цену -1, forged identity/owner oracle, stale generation, no proposal aliases, missing/extra N9 accounts, duplicate FIFO waiter. Пять исходных N39/N21/N9 тестов также прошли. Полные 100/500 actor fixtures и отдельные сценарии занятости дока НЕ завершены.

## Godot 4.7.2 / CI

- Первый run: https://github.com/Mefits/Living-Sector/actions/runs/43727865302 — **FAIL parser**, случайная замена подстроки `physical_world.duplicate`/`before_world.duplicate`; исправлено в `340d156`. До simulation не дошёл.
- Второй run: https://github.com/Mefits/Living-Sector/actions/runs/43728191148 — **PASS** parser и шесть целевых тестов, но FAIL нового profiling test (повторная переменная `stats` в одном GDScript scope), исправлено `f832da6`. А/B не запускался.
- Третий, текущий run: https://github.com/Mefits/Living-Sector/actions/runs/43728402372 — parser и шесть тестов PASS, A/B 420 / N38 restart360 и 900 ожидают окончательных результатов. Один `ubuntu-24.04` runner, один Godot 4.7.2, оригинальный seed, полные hashes `JSON.stringify(checkpoint).sha256_text()`, не только summary; baseline N39 берётся ровно из `823f323...`.
- Исходный полный `Schema.validate`, N9 journal, N38 save/restore, dispatch, route_graph, N158, ticks, money and balance не ослаблены/не менялись.

## Только наши изменённые файлы

`godot/scripts/sim/phase1/n39_native_world_production.gd`,
`godot/scripts/sim/phase1/n39_market_observation_validator.gd`,
`godot/tests/p2_parallel_a_market_version_validator_check.gd`,
`godot/tests/p2_parallel_a_checkpoint_fingerprint_check.gd`,
`.github/workflows/p2-parallel-a-n39-validator-proof.yml`,
`godot/docs/phase2/handoffs/*parallel-a*.md` (этот handoff), и ранее зарезервированный lease. Запрещённые файлы не затронуты.

## Следующая итерация

1. Прочитать третий CI run, извлечь точные A/B 420 (baseline/candidate ms, совпадение всех SHA256 state), 900 status, p95 и дорогостоящие callsites.
2. При mismatch/FAIL — искать конкретный domain и исправлять **только свои файлы**. При ухудшении общей производительности откатить или скорректировать недоказанную оптимизацию, оставить oracle.
3. Доделать A4 N21 dock narrow proof и A7 валидные нагрузочные fixtures; не принимать длину Rust N21 waiting FIFO за число занятых docking slots. Контрольная стадия `_admit` отдельно проверяет occupancy против capacity.
4. Отметить статус в tldraw только у чата №1. До полного PASS/merge оставить оранжевым. По завершении предоставить PR отчёт; зелёным отмечает только координатор после review и merge.

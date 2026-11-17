# PERF RECOVERY — независимый Gate 0, 17.11.2026

**Статус: BLOCKED / TEST_UNVERIFIED на экспериментальном HEAD. Ни один новый hotspot не выдан разработчикам.**

## Идентификаторы и доступность

- Экспериментальный код: `dd1f859462900473598410d1d32d7daf6618db9f`; текущая recovery-ветка содержит только два коммита документации поверх этого SHA. Исполняемый код идентичен `dd1f859`.
- Ранее коротко проверенный код: `5829f93dc7555329e4fe61cf76a289900f414ea8`; [GitHub Actions #44027858762](https://github.com/Mefits/Living-Sector/actions/runs/44027858762), PASS 17.11 05:59–06:00 UTC.
- Новых workflow runs на recovery-ветке при проверке нет. У доступного GitHub connector есть чтение workflow/jobs/logs и повторение существующих failed jobs, но **нет workflow_dispatch для произвольной ветки**. Предусмотренные `p2-pr262-head-500-acceptance.yml`, `p2-perf-262-601-tick-phase.yml` и `p2-late-growth-owned.yml` содержат `workflow_dispatch`, однако push-триггеры ограничены старой веткой. Локальный container не имеет DNS-доступа к github.com, поэтому checkout текущей ветки и локальный Godot run недоступны. Запускать старые workflows на другом SHA, выдавая их за новый HEAD, нельзя.

## Проверенные ранее результаты, НЕ сравнение текущего кандидата

В #44027858762, seed `native_current_world`, 24 ships, настоящие оплаченные тики: window avg **47.73 ms/tick** at tick100, **68.98** at tick300, **82.53** at tick500. 500 paid ticks PASS; worker boot/N38 PASS; same-seed 160-tick legacy/optimized parity 5/5 exact checkpoints PASS (11.71s vs 9.04s для отдельного 160-tick теста). Это **не измерение dd1f859**.

Исторический source profile на **другом, более старом SHA**: [#43856475886](https://github.com/Mefits/Living-Sector/actions/runs/43856475886), 16.11.2026. Окна: tick100 137.00ms, tick300 284.55ms, tick600 469.61ms, tick900 786.21ms; прогон завершился на tick969 по wall budget. **Tick1200/2000/2600 не достигнуты.** По 601–900: ships 117648.26ms/300 = **392.16ms/tick**, 300 phase calls; markets 39429.73/300 = **131.43ms/tick**, 300 calls; factions 39344.79/300 = **131.15ms/tick**, 300 calls; dock_queue 26485.41/300 = **88.28ms/tick**, 300 calls. Deep World copy `deep:L129` 34660.58ms / 2929 calls = **115.54ms/tick** в том же окне, **вложенный** расход, НЕ складывать его с фазами; `deep:L196` 7414.81ms/300 calls = 24.72ms/tick. Эти профили подтверждают **исторические** проблемы, но после 149 коммитов между 5829 и dd1f859 нельзя считать их текущими.

## Невыполненные условия Gate 0

1. Запустить существующий короткий `p2-pr262-head-500-acceptance.yml` именно на `integration/perf-recovery-20261117` (код dd1f859) через workflow_dispatch или другой контролируемый механизм, не трогая старую ветку. Проверить compile, GUI worker/N38, 500 paid ticks, targeted negatives, 160 exact parity.
2. На **том же SHA и одинаковом seed/runner configuration** выполнить bounded late source phase profile и сравнение с 5829f93. Если 1200/2000 недостижимы — зафиксировать последний реально оплаченный тик и предел wall budget. Измерить copy counters, N152, ships, dock, markets/factions, N9 и память.
3. Только после результатов опубликовать **top-2 текущих независимых hotspots**: исходный путь/функция, paid window, calls, ms/tick, before/after SHA, критерий приёмки. До этого CORE/FLOW — **NO_COMMIT**.

**Решение VERIFY:** нет оснований принимать новые оптимизации или выдавать Core/Flow задачи по старым цифрам. Исходная ветка и stable не изменены.

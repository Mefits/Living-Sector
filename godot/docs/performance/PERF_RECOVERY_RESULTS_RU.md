# PERF RECOVERY — независимый Gate 0, 17.11.2026

## Windows-профиль от пользователя — предварительные тики 100 и 300

**Доказательство:** пользователь загрузил в чат фактический `late-growth.log` из локального Godot 4.7.2. Лог содержит полные строки `LATE_GROWTH_EXTRA` и `P2_PERF_E_LATE_TICK_WINDOW` только для тиков **100** и **300**; маркера `P2_PERF_E_LATE_TICK_BOUNDED_PASS` / стоп-причины и 600+ **НЕТ**. Исходный запускаемый PowerShell предыдущего сообщения пользователя показал закреплённый commit `dd1f859462900473598410d1d32d7daf6618db9f`, но SHA НЕ содержится в самом позднетиковом логе. Статус `WINDOWS_PARTIAL_300`, **НЕ late soak PASS, НЕ полная измерительная готовность**.

| Метрика | тик 100 | тик 300 |
| --- | ---: | ---: |
| Avg actual paid tick, last 100 | 98.21 ms | 133.46 ms |
| P95 actual paid tick, last 100 | 152.87 ms | 218.41 ms |
| Runtime cumulative | 9.84 s | 33.40 s |
| Ships, count | 24 | 24 |
| Ships phase totals/calls | 5906.11ms/100 = 59.06ms/paid tick, 1–100 | 13004.78ms/200 = 65.02ms/paid tick, 101–300 |
| Factions phase totals/calls | 1829/100 = 18.29ms/tick | 5614.66/200 = 28.07ms/tick |
| Markets phase totals/calls | 831.42/100 = 8.31ms/tick | 2098.42/200 = 10.49ms/tick |
| deep:L129 World-copy totals/calls | 388.02ms / 227 = 1.71ms/copy | 1361.14ms / 458 = 2.97ms/copy |
| research_receipts bytes | 158068, 300 rows | 246560, 468 rows |
| markets bytes (3 markets) | 25752 | 55452 |
| ships bytes | 83320 | 83520 |

Нюанс: `P2_PERF_E_LATE_TICK_WINDOW` сообщает elapsed tick avg по ПОСЛЕДНИМ 100 тикам; phase/copy totals на 300 — это разность от предыдущей контрольной точки, то есть 101–300 (200 тиков). Не приравнивать эти интервалы и не суммировать вложенные `deep:L129` с фазовыми расходами как независимые расходы.

Наблюдения: уже до tick300 оплаченный тик дороже на ~35.9%; ships остаются 24, растут истории/markets. `deep:L129` — подтверждённая стоимость внутри N39, примерно 2.3 вызова/тик, удорожание ~74% на один copy между периодами 1–100 и 101–300. Это **кандидат на root-cause**, не доказательство причинности и не основание менять код до более поздних окон и независимого A/B. Ships и factions также основные фазы. `runtime_read:engineer_dispatch` и ship_motion учтены в профиле, не дублировать существующие фиксы N158.

**Действие VERIFY:** учесть этот измеренный ранний baseline; запросить полный `late-growth.log` после конца исполнения (или `late-growth.stderr.log` при завершении с ошибкой) и `perf-summary.json`, желательно после тиков 600/900/1200+. Не запускать GitHub Actions. `HOTSPOT_VERIFIED` для CORE/FLOW/GROWTH/SCALE пока НЕ назначать. Можешь подготовить статический план независимых файлов на основе текущего N39 L129, ships и factions, но НЕ выдавать задачи на исправления под видом измеренного позднего hotspot.

---


## Вне GitHub Actions: готовый локальный профилировщик

Есть конкретный способ получить свежие измерения без расхода GitHub Actions, **но он требует одного запуска на Windows пользователя или отдельной машине с Godot**. Сам чат не имеет ни Godot в своём контейнере, ни доступа к Windows пользователя.

- Скрипт: `godot/tools/perf_recovery_local_probe.ps1`, ветка `integration/perf-recovery-20261117`.
- Использует зафиксированный реальный код `dd1f859462900473598410d1d32d7daf6618db9f`, извлекает его в **временный отдельный git worktree**. Ничего не переключает/коммитит в `feature/SystemBalance`.
- Включает `LS_PROFILE_NATIVE_PHASES=1`; запускает существующий Godot `p2_late_growth_capture.gd`. Пробует дойти до 2600, но сам тест прекращается после 8 минут; ничего не объявляет пройденным, если бюджет исчерпан. Каждые 100/300/600/900/1200 и т.д. сохраняет числа ms/тик, phase/copy/schema calls. PowerShell-скрипт сохраняет в папку Документы/LivingSectorPerf/probe-*/ файлы `perf-summary.json` и `late-growth.log`.
- На Windows с Git + Godot 4.7.2 из любой ветки проекта можно скачать этот скрипт отдельно во временный каталог и выполнить с `-RepoRoot D:\PROGRAMS\Living-Sector`. Пользователь должен сам разрешить локальный запуск; автоматическая задача его ПК не контролирует.
- После получения `perf-summary.json` и `late-growth.log` надо прикрепить их в чат либо дать VERIFY доступ к результатам через GitHub. До этого `HOTSPOT_VERIFIED` нельзя записывать по свежему коду, а четыре роли остаются блокированы. Не компенсировать отсутствие данных дополнительными Github Actions.

После результатов VERIFY назначает независимые top-4 только с числами (seed/SHA/tick window/ms per paid tick/calls) и фиксированными owned_files. Это **путь передачи данных**, а не утверждение, что они уже получены.

---


## Обновление по бюджету CI — 17.11.2026

**Уточнение после первичного отчёта:** проверка уже была выполнена, хотя на момент первого чтения run отсутствовал в списке. [Actions #44137306259](https://github.com/Mefits/Living-Sector/actions/runs/44137306259), SHA `7cca583b75b2de911336565b0628a3dfc3d4696a`, **SUCCESS**: import/compile, Worker/N38, 500 настоящих оплаченных тиков и 160 exact checkpoint parity. Этот SHA содержит прежний экспериментальный код `dd1f859`; на уровне функциональной короткой проверки Gate0 пройден. **Поздний профиль и fresh same-seed 900–2600 НЕ выполнены; PERFORMANCE_GATE остаётся BLOCKED, top-4 hotspot НЕ выданы.**

По прямому распоряжению пользователя дальнейшие GitHub Actions резко ограничены: не запускать CI по коммитам/итерациям, только вручную короткий <=4-минутный workflow, максимум один в сутки по необходимости. Старый длинный Gate0 workflow заменён на opt-in short, содержащий только import/compile, 2-tick Worker/N38 и две targeted negatives. Длинные позднетиковые прогоны только вне GitHub Actions. Если локальная среда недоступна, сообщить об ограничении, НЕ создавать workflow и не пытаться получить новый CI принудительным push. Это уточнение **выше** устаревшего фрагмента ниже про «нет GitHub run».

---


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

## Попытка разблокировать CI в этом запуске

Создан **один** workflow `.github/workflows/p2-perf-recovery-gate0.yml` на recovery-ветке (commit `7cca583b75b2de911336565b0628a3dfc3d4696a`). Содержит import+compile, реальный worker/N38 boot, 500 paid ticks и exact 160-tick parity с сохранением артефактов. Workflow настроен на push нового собственного YAML или ручной dispatch; **первичная проверка списка Actions не показала run на recovery-ветке**, поэтому ни один тест этого Gate 0 нельзя считать запущенным или пройденным. Следующая итерация сначала проверяет, появился ли run, затем его логи и при необходимости выбирает поддерживаемый способ запуска; не плодит новый workflow и не запускает тяжёлый late-run до PASS короткого Gate 0. Этот workflow не содержит позднетикового профиля; для него потребуется отдельный ограниченный прогон после короткого PASS.

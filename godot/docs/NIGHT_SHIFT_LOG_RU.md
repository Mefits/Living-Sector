# Living Sector — журнал ночных запусков (12 ноября 2026)

**Этот файл читается и обновляется каждым запуском** совместно с [NIGHT_SHIFT_QUEUE_RU.md](NIGHT_SHIFT_QUEUE_RU.md) и [протоколом резерваций](nightshift/CLAIM_PROTOCOL_RU.md).

## Текущее состояние перед ночной сменой

- P0: **3/9 VERIFIED** по архиву и проверке исходных данных; в Godot Editor ещё не запускалось.
- P1: **0/9 VERIFIED**; код P1-A орбитных тиков, кнопок и P1 checkpoint есть, но Godot Runtime не проверен.
- Всё: **3/100 VERIFIED**.
- Открытая последовательность PR #84 → #85 → #86 → #87; последний PR — `feature/godot-p1-ticks-orbits-saves`.
- Координационная ветка — `feature/godot-nightshift-20261112`. Удобно использовать её только для очереди/claims, код каждого блока — **в отдельной ветке/PR**, чтобы два чата не перезаписывали друг друга.
- Критерии зачёта: реальный тест либо достоверный вывод GitHub/API; статическая проверка без Godot Runtime = `CODE_UNVERIFIED`.
- **Занято сейчас:** никто. Файлы `claims/Nx.json` пока не созданы.

## Формат записи после каждого запуска

### Запуск №X — точная дата-время и владелец

- **Забронировано ДО начала:** `claims/Nx.json`, `IN_PROGRESS`, ссылка на коммит.
- **Проверено:** источники Rust, технические аналоги Godot и опыт разработчиков (ссылки).
- **Выполнен большой блок:** 3–5 связанные задачи, список файлов/коммитов и PR.
- **Мини-тест:** точная команда/результат либо честно «Godot не запускался».
- **Передача:** status, next TODO/block, зависимости и ограничения.
- **Текущее состояние:** P0 x/9, P1 x/9, P2 x/11, всего x/100. Отдельно отмечаем написанное без запуска.

**Все последующие записи добавлять в конец, не стирать историю других чатов.**

### Запуск N2 — 2026-11-12 03:20:46 +03:00 — second-chat-overnight

- **Забронировано ДО разработки:** `claims/N2.json`, `IN_PROGRESS`, commit `e3f7c8524fdc3710712c2c818e69ceeb79b36067`.
- **План:** календарь, независимость симуляционных тиков от FPS, обратимая настройка длительности тика, snapshot/UI и smoke-тест.
- **Рабочая ветка:** `feature/godot-nightshift-n2-calendar-second-20261112`.
- **Статус:** работа начата; результат будет записан ниже.

### Итог N2 — second-chat-overnight

- **Код:** календарь нативных единиц, только по исполненным тикам; checkpoint/restore с сохранением неизвестной эпохи старого сейва; UI-статус; отдельный headless smoke.
- **Источник:** Rust `simulation/config.rs`: 8 TPS, world_speed=0.25, tick_scale=speed/TPS; час/тик не утверждён.
- **PR:** https://github.com/Mefits/Living-Sector/pull/89 (draft, без merge); head `ff397f6ec5b193034460ef39a0255a9d557725b2`.
- **Проверки:** сравнение формулы с Rust; ручная статическая сверка GDScript; Godot executable отсутствует, тест НЕ запускался. Статус `CODE_UNVERIFIED`.
- **Другие блоки:** при резервировании N1 и N3 не имели claim; дальнейшие захваты проверять заново.
- **Дальше:** N3 deterministic event queue / integer SimTime; N2 сначала прогнать `n2_calendar_check.gd` в Godot.
- **Текущее состояние:** P0 3/9 VERIFIED, P1 0/9 VERIFIED, P2 0/11 VERIFIED, всего 3/100 VERIFIED; N2 один блок кода без проверки Godot.


### Запуск N1 — 2026-11-12 03:25:36 +03:00 — third-chat-overnight

- **Забронировано ДО разработки:** `claims/N1.json`, `IN_PROGRESS`, commit `fcf19f782857467fcc95f65406922ac1ab1823c6`.
- **План:** статический аудит P0/P1-A, точная сверка Rust-формул и ссылок, исправления smoke-проверок без имитации runtime-приёмки.
- **Рабочая ветка:** `feature/godot-nightshift-n1-static-audit`.
- **Статус:** работа начата; результат будет записан ниже.


### Итог N1 — third-chat-overnight

- **Код:** PR #90 усиливает границы native seed/WorldModel, не допускает ложных нулевых орбит и не позволяет live pause/resume расходиться с восстановлением checkpoint; добавлен третий headless smoke.
- **Источники/решение:** Rust P1 формула орбиты сохранена; использованы штатные Godot `Dictionary`, `is_finite`, `JSON` и headless CLI — плагин для 47 тел не нужен.
- **PR:** https://github.com/Mefits/Living-Sector/pull/90 (draft, без merge); head `c96dd597383051b0645a18fd10fee0e76996d977`.
- **Статически проверено:** 8 frozen Galaxy JSON распарсены; 47/47 тел удовлетворяют `orbit_period > 0`, `0 <= current_angle < 360`; изменённые файлы просмотрены на сбалансированность структур.
- **Не подтверждено:** Godot executable отсутствует; `RUN-P1-SMOKE.cmd` (P0 + P1 + P1 audit) не запускался, поэтому N1 = `CODE_UNVERIFIED`.
- **Другие блоки:** N2 завершён как `CODE_UNVERIFIED` в PR #89; N3 и далее проверять по claims перед захватом.
- **Дальше:** N3 — детерминированная очередь событий/cadence; утром прогнать оба P1 smoke и N2 calendar smoke.
- **Текущее состояние:** P0 3/9 VERIFIED, P1 0/9 VERIFIED, P2 0/11 VERIFIED, всего 3/100 VERIFIED; 2 существенных блока кода без проверки Godot (N1, N2).

### Запуск N3 — 2026-11-12 03:35 +03:00 — second-chat-overnight

- **Claim:** `claims/N3.json`, `IN_PROGRESS`, commit `9fcc20b5ab74ca511ca9dcfb24bcce10ceb35a43`.
- **План:** cadence, детерминированные события, отмена/дедупликация, snapshot и короткий smoke.
- **Ветка:** `feature/godot-nightshift-n3-events-second-20261112`.

### Итог N3 — second-chat-overnight — 12.11.2026

- **Реализовано:** `event_queue.gd` (строгий порядок due_tick/phase/entity_id/sequence, дедупликация, отмена, сохранение), `cadence.gd` (период/offset), подключение к `tick_runner.gd` с сигналом событий и атомарным восстановлением, `n3_events_check.gd`.
- **Источник:** замороженный Rust `native/crates/sim_server/src/engine.rs`; порядок фаз сохранён, экономические фазы не имитируются. Godot `RefCounted`, `Array.sort_custom`, сигналы; без тысяч Nodes и внешних плагинов. Паттерн Event Queue из Game Programming Patterns.
- **PR:** https://github.com/Mefits/Living-Sector/pull/91, head `8fa6e298e96feaaabfeb26f36d177b14f31ef9fd`, база PR #89, draft, без merge.
- **Проверка:** баланс скобок четырёх GDScript файлов; Godot Runtime отсутствует, `n3_events_check.gd` не запускался. **CODE_UNVERIFIED**, не VERIFIED.
- **Утром:** `godot --headless --path godot --script res://tests/n3_events_check.gd`, затем `RUN-P1-SMOKE.cmd`; исправить любые runtime ошибки до merge.
- **Зависимости:** PR #89 N2; другие блоки сверять по claims. Следующий независимый N4 registry либо N5 commodities, после свежей проверки занятости.
- **Текущее состояние:** P0 3/9, P1 0/9, P2 0/11, общий 3/100 VERIFIED.

### 2026-11-12 02:00 CET — N4 started (overnight-scheduler)

Reserved `N4.json` atomically; implementing native registry and travel route graph in `feature/godot-nightshift-n4-registry-routes-overnight-20261112`. Godot runtime validation pending.

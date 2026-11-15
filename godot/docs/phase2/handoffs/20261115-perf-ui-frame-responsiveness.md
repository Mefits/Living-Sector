# Living Sector · FPS / frame responsiveness · чат №1 · 2026-11-15

**Статус: КОД В PR #259 / ОРАНЖЕВЫЙ / WINDOWS RUNTIME НЕ ПРОВЕРЕН.**
Репозиторий: https://github.com/Mefits/Living-Sector
Собственная ветка: `feature/perf-ui-frame-responsiveness-20261115`.
Draft PR: https://github.com/Mefits/Living-Sector/pull/259
Исходная интеграция: `integration/godot-phase2-unified-20261113`, стартовый HEAD **`5f280ca617c874333dfd48410d6455e005a11361`**. PR #257/#258 уже merged на момент создания ветки.
Зона: `godot/scripts/main.gd`, `star_system_view.gd`, `system_map.gd`, `observer_panel.gd`, новый `ui_frame_profiler.gd`, собственные `p2_ui_*.gd` и этот handoff. **N39/N158/TickRunner/Ledger/N153/AI/координаты/баланс не менялись.** GitHub Actions **не запускались** по просьбе пользователя.

## Очередь U1–U8 и точные коммиты

| Этап | Статус | Коммиты | Результат / что проверить |
| --- | --- | --- | --- |
| U1 FPS и диагностика | **IMPLEMENTED / NOT YET RUNTIME VERIFIED** | `d1c2b01`, `47c6582`, `527db47`, `46608ec`, `1c8d233`, `1008855`, `e0ece3f`, `cba4027` | Постоянный Engine FPS; **реальный frame delta p95**, process/advance/UI avg+p95, локальный и all-time worst frame, тик +N / total; метрики не создают World snapshot; вывод в tooltip и опциональный JSON каждые 5 секунд |
| U2 реальный источник UI блокировок | **INSTRUMENTED / WINDOWS DATA PENDING** | `47c6582`, `49f0d80`, `e0ece3f`, `cba4027` | Исходный `_process→advance_frame` синхронен; теперь отдельно measured `advance_frame`, post-tick UI и draw CPU. `advance_frame` включает N158+любые чужие callbacks; вне процесса GPU/VSYNC не измеряются |
| U3 Observer | **IMPLEMENTED / NOT YET RUNTIME VERIFIED** | `9a21f9d`, `49f0d80`, `d65f958`, `4e460f6`, `09ddb4a` | При открытом Observer используются одни данные завершённого N38 checkpoint для экономики, кораблей, inspector/status; основная вкладка «Сводка» не собирает скрытые длинные разделы; выбор подробного раздела запрашивает новый canonical checkpoint |
| U4 star_system_view | **IMPLEMENTED / NOT YET RUNTIME VERIFIED** | `f89784b`, `306fd51`, `bd88a9f` | Body ID→body, body→facility count, location→body IDs, body→live ship count, max orbit radius; deep clone только изменённого визуального домена, а не всего World; арки/углы native unchanged, планеты и N14 transits не интерполируются |
| U5 system_map | **IMPLEMENTED / NOT YET RUNTIME VERIFIED** | `5e61d26` | Единожды source native coordinates + bounds; fit recompute только на explicit set_worlds или resize; redraw selected only when changed; оригинальные universe_offset и routes неизменны |
| U6 UI update frequency | **IMPLEMENTED / NOT YET RUNTIME VERIFIED** | `47c6582`, `9a21f9d`, `49f0d80`, `09ddb4a`, `ec33c5b` | `tick_completed` **только** ставит pending tick; после `advance_frame` за один render-frame одна sample свежего орбитального состояния, fleet каждые минимум 4 завершённых тика; тяжёлые панели раз в 0,45 wall second **и только если tick изменился** |
| U7 worker / responsiveness | **DESIGN COMPLETE / IMPLEMENTATION BLOCKED BY N158 OWNERSHIP** | этот handoff | Не внедрял Thread/unsafe shared mutable Dictionary. Нужен отдельный N158/TickRunner интерфейс атомарной фоновой транзакции — ниже |
| U8 проверка и Windows | **TESTS AUTHORED / WINDOWS FPS PENDING** | `032e279`, `fb834ec`, `0b1d5ac`, `09ff1ba`, `89fef75`, этот handoff | Два изолированных Godot SceneTree теста и матрица 16 профилей. Локального Godot 4.x в среде исполнителя нет. Никаких фиктивных цифр FPS. |

## A. Что действительно происходило в исходном UI

До PR #259 `main.gd::_process(delta)` прямо вызывал синхронный `_runner.advance_frame(delta)`. Внутри N158 исполнялись `tick_completed` callbacks главной сцены. Один из них на 8-м тике вызывал `_refresh_observer`, `_refresh_selection` и `_update_status` **пока advance_frame ещё не завершился**; на промежуточных тиках мог снова переписывать систему и дублировать fleet. В `_select_world` дополнительно дважды независимо вызывался `_runner.economy_snapshot()` для рынков и населения. Любая такая работа блокировала главный GUI поток.

**После PR:** во время расчёта main получает лишь `_pending_ui_tick = tick`. По завершении всех тиков текущего GUI кадра отдельная presentation phase берёт только **последнее реально завершённое** состояние. Если Observer открыт, уже созданный detached `checkpoint.native_production.world` идёт и в Observer, и в selection/status, **а также в visual fleet при совпадении цикла**, без следующих глубоких копий для той же презентации. Если Observer закрыт, один `economy_snapshot()` используется на все обновляемые панели. При отсутствии завершённого тика тяжёлые обновления не выполняются.

Объективное ограничение: **сама симуляция N158 остаётся синхронной**, поэтому кадры всё ещё могут длиться дольше 16,7 мс даже при практически нулевой стоимости GUI. Профиль сначала покажет, является ли это основной причиной.

## B. Что именно измеряет профиль

В верхней строке отображается компактный постоянный `FPS <...> · кадр p95 · sim+signals p95 · UI p95 · тик +N`. Наведение мыши показывает полную диагностику:

- `fps`: **реальный Engine.get_frames_per_second()**, а не 1 / стоимости N39 тика;
- `frame_p95_ms`, `frame_window_max_ms`: монотонное wall-time между вызовами `_process` (включает предыдущую отрисовку и возможный блокирующий тик; окно последних 120 GUI кадров). `worst_frame_ms` — худший за весь запуск;
- `process_avg_ms`, `process_p95_ms`, `worst_process_ms`: собственный замер CPU времени внутри `main._process`;
- `advance_avg_ms`, `advance_p95_ms`: всё время внутри N158 `advance_frame` (симуляция + возможные посторонние signal handlers), **не называйте это строго чистой симуляцией**; также `advance_share_of_process_pct`, `advance_over_16_7ms_window` и `frame_over_16_7ms_window` показывают число нарушений бюджета 60 FPS в последних 120 кадрах;
- `ui_avg_ms`, `ui_p95_ms`: только наша `_flush_finished_tick_views` ПОСЛЕ advance; `ui_share_of_process_pct`, `ui_over_16_7ms_window` помогают отличить UI от симуляции;
- `draw_cpu`: время выполнения `_draw` видимой карты/системы, last/max/calls; **не GPU и не стоимость VSYNC**;
- `ticks`, `last_frame_ticks`, `ticks_per_frame_window`: реальное количество завершённых N158 тиков, никаких дополнительных `tick()`.

Нельзя складывать отдельные p95 как обычные скаляры, они относятся к разным кадрам. Делать вывод об источнике лагов по **одному** FPS или усреднённому профилю без UI вариаций нельзя.

## C. Windows — короткая проверка без GitHub Actions

1. Скачайте актуальную **ветку PR #259** (не старую main/integration), откройте Godot 4.x / 4.7.2 проект в `godot` и включите запуск игры. На экране должен быть постоянный FPS счётчик. Сначала проверьте, что запускается парсер и нет ошибок.
2. Чтобы получить численный лог, из PowerShell откройте папку `godot` и запустите **консольную** сборку Godot (путь и имя EXE замените на свои):

   ```powershell
   & "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --path . -- --p2-ui-profile 2>&1 | Tee-Object -FilePath .\ui-profile-windows.log
   ```

   Каждые 5 секунд появляется одна строка `P2_UI_FRAME {...}` с фактическими `speed`, `paused`, `view` и `observer`. Аргумент — только диагностика UI; внутрь N158 он не передаётся.
3. Отдельно локально запустите два собственных теста:

   ```powershell
   & "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/p2_ui_frame_profiler_check.gd
   & "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/p2_ui_visual_indices_check.gd
   ```

   Маркеры успеха: `P2_UI_FRAME_PROFILER_PASS`, `P2_UI_VISUAL_INDICES_PASS`. **Пока тесты не запускались** здесь.
4. Для 16 состояний: пауза, ×1, ×8, ×16; **сектор/система** × **Observer закрыт/открыт**. После смены состояния дайте 5 секунд на очистку короткого rolling-window профиля, затем соберите 2–3 строки (`P2_UI_FRAME`). Не сравнивайте снимки в первые секунды загрузки. Для каждой пары лучше использовать одно и то же сохранение и одинаковый игровой тик. При паузе честно ожидается `last_frame_ticks=0`, но FPS должен оставаться измеримым.
5. При открытой системе проверьте Earth/Luna, точность орбит, реальные корабли в доках и в пути; приближение/отдаление, выбор планеты, возврат в сектор. Никаких прыжков координат, увеличения количества кораблей или изменения N9 из-за UI.

## D. Таблица измерений — **пока пустая, требуется Windows**

Поля: FPS; whole-frame p95; `advance_frame` p95; post-sim UI p95; draw last CPU; worst кадр за последние 120 GUI кадров. N158 по-прежнему получает **исходный Godot delta**, а profiler измеряет кадр отдельно через `Time.get_ticks_usec()`. Все значения — *real local Windows*, не headless.

| Скорость | Экран | Observer | FPS | Кадр p95, мс | Advance p95, мс | UI p95, мс | Draw CPU, мс | Worst window, мс |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Пауза | Сектор | закрыт | — | — | — | — | — | — |
| Пауза | Сектор | открыт | — | — | — | — | — | — |
| Пауза | Система | закрыт | — | — | — | — | — | — |
| Пауза | Система | открыт | — | — | — | — | — | — |
| ×1 | Сектор | закрыт | — | — | — | — | — | — |
| ×1 | Сектор | открыт | — | — | — | — | — | — |
| ×1 | Система | закрыт | — | — | — | — | — | — |
| ×1 | Система | открыт | — | — | — | — | — | — |
| ×8 | Сектор | закрыт | — | — | — | — | — | — |
| ×8 | Сектор | открыт | — | — | — | — | — | — |
| ×8 | Система | закрыт | — | — | — | — | — | — |
| ×8 | Система | открыт | — | — | — | — | — | — |
| ×16 | Сектор | закрыт | — | — | — | — | — | — |
| ×16 | Сектор | открыт | — | — | — | — | — | — |
| ×16 | Система | закрыт | — | — | — | — | — | — |
| ×16 | Система | открыт | — | — | — | — | — | — |

## E. U7 — безопасный контракт для будущего N158 worker (BLOCKED, не менять из UI ветки)

`advance_frame` сейчас обязан завершать корректный N39/N9/BT/RNG/contract/tick commit **синхронно**. `main.gd` не может безопасно отправить этот объект в `Thread` и одновременно читать его изменяемые `Dictionary`, `Node`/`SceneTree`, `Resource`, `Signal` или shared Ledger. Это создало бы гонки, повреждённые чеки и рассинхронизацию N38.

Координатор / владелец N158 должен сначала выделить контракт `TickRequest` из **полностью detached immutable bytes**, чистую операцию `run_owned_tick(request_bytes) -> TickResult` без SceneTree/Renderer/Node/жёстких ссылок на UI, и `publish_finished_tick(result)` **на главном потоке, атомарно**, с проверкой исходного generation и всеми прежними N9/N38 инвариантами. Не более одного in-flight тика; все pause/step/speed/save команды и RNG state маршалируются детерминированно по границам commit. UI получает только immutable завершённый `FrameView`/delta, а не mutable live World. Отказ или устаревший результат не публикуется. Доказать full-state equality baseline vs worker для 420/900/N38 и ошибки paid receipt прежде, чем запускать Thread.

Предпочтительный промежуточный вариант — **контролируемый nonblocking copy-free readonly FrameView API** с generation по завершённому N158 тику; это снижает стоимость UI observer без параллельного экономического Apply. Как альтернатива кооперативная пофазная машина состояний с atomic-final commit, но делить один денежный тик без владения N158 нельзя.

## F. Финальные границы

Не запускались GitHub Actions. В текущей среде **нет Godot бинарника**, локальный parser/runtime FPS не подтверждён. Изменения — UI source + тесты, а не заявленное FPS ускорение. База до UI работы фиксирована, PR #259 остаётся **Draft**, строго orange до review и merge. Следующий шаг по команде «Продолжай»: проверить Windows лог/ошибки (если доступны), исправить несовпадения, затем сдать coordinator handoff, не касаясь зоны второго чата.

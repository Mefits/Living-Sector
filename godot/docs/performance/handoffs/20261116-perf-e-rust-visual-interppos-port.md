# PERF E — восстановлена Rust/Bevy визуальная интерполяция в Godot

Дата: 16.11.2026. Репозиторий `Mefits/Living-Sector`, **только** `integration/perf-astra-5-workers-20261116`, черновой PR #262. Никаких отдельных PR или merge.

## Причина и подтверждённый Rust-эталон

После реального N158 worker на Windows пользователь получил стабильные ~60 FPS интерфейса при x16, тик ~585, но планеты и корабли двигались рывками.

В `native/crates/client_bevy/src/render/mod.rs` Rust/Bevy сохранял две физические позиции `InterpPos.prev/curr` после `FixedUpdate` (`snapshot_tick_positions`) и использовал `lerp(alpha)` из `Time::<Fixed>::overstep_fraction()` каждый `Update` (`sync_positions`). Godot отображал углы из последних завершённых N158 тиков напрямую, а полный snapshot флота запрашивался приблизительно раз в 450 мс. В результате плавность камеры от нового worker не означала плавность движущихся тел.

## Код

- `godot/scripts/ui_source_motion_interpolator.gd` — чистый UI-only модуль с ограниченной по времени `alpha`, коротким `orbit_angle` (с корректным переходом 359°→1°) и `transit_position` только между двумя подтверждёнными валидными координатами.
- `godot/scripts/star_system_view.gd` — при новых source body/ship snapshots сохраняет прежнюю *показанную* позицию, не мутируя `WorldModel`, N39, N158, N9 или сохранения N38. `_process` запрашивает `queue_redraw()` только в течение перехода; `_draw` получает интерполированные визуальные углы, Luna наследует фактическую проекцию родительской планеты. Для реально летящих кораблей рендер интерполирует `transit.position`; при новом system ID, вылете/прибытии или отсутствии transit мгновенно показывает новое подтверждённое положение без вымышленного полёта.
- `godot/tests/p2_perf_e_visual_interpolation_check.gd`: positive/negative регрессии wrap, clamp alpha, короткий lerp, invalid coordinates, no alias/source mutation, system change, docking/arrival, reset.
- `.github/workflows/p2-perf-e-visual-motion-short.yml` — parser + targeted test + 32 real N158 worker ticks, hard 8-min limit.

Никаких правок `main.gd`, `n39`, `n9`, clock, каденса, экономики или AI. На 32-tick PASS проверяется конкретно существующий worker-F5 с новым UI классом; измерение не доказывает визуальную плавность Windows.

## Реальные коммиты и проверки

Код: `f5369cb8` (pure helper), `f6f25ed7` (live `StarSystemView`), `8bcc5a46` (validated XY predicate).
Тест: `0fe187e4`, `544289de`; CI: `b40dd529`.

**PASS**: https://github.com/Mefits/Living-Sector/actions/runs/43852644926

- Godot 4.7.2 Linux, full import/compile: PASS.
- UI interpolation script with actual SceneTree view and negative cases: PASS.
- Worker GUI 32 paid ticks, 24 source ships, 573 headless GUI frames / 3.97s, `_process` p95 1.51ms: PASS.

Новых Windows FPS/визуальных кадров **ещё нет**. Source economic ticks и native ship progression останутся тяжелыми; сглаживание лишь воспроизводит Rust-представление между подтверждёнными состояниями.

## Следующее действие

Пользователь: подтянуть ту же ветку PR #262, перезапустить Godot и F5 (WORKER), посмотреть орбиты/корабли при x16 на тиках ~300–600; сообщить, исчезли ли рывки и что осталось. Если предметы ещё подёргиваются — измерить интервалы source-angle/source-fleet commits и profiler; не включать скрытые новые тики или безосновательную экстраполяцию. Для больших флотов следующим шагом может понадобиться отдельный лёгкий transport visual snapshot, без тяжёлого полного N38/World кадра.

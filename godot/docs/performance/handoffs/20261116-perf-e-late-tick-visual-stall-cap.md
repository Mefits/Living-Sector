# PERF E — поздние тики: устранён жёсткий визуальный freeze после 650 мс

Дата: 16.11.2026. Работа **только** в общей ветке `integration/perf-astra-5-workers-20261116`, draft PR #262. No merge.

## Наблюдение Windows

Пользователь подтвердил: новый F5 WORKER (x16, камера ~60 FPS) и Rust-style InterpPos работают; планеты и корабли плавно движутся, но с ростом tick начинают останавливаться между source updates. Старый скрин tick2329: WORKER sim ~1430.1ms; на раннем tick~585 sim ~147.3ms. Overlay `sim_usec` — время исполнения одного owner command до сериализации economy/frame, **не гарантированно** одного оплаченного tick; нужно позднее отдельно измерить `tick_delta` и фазовую цену. Рост серьёзный, FPS 60 его скрывает.

## Корневая причина визуального freeze

`godot/scripts/ui_source_motion_interpolator.gd::sample_duration()` ограничивал display-only tween максимальным `650000` мкс. Когда следующий completed N158 state приходит спустя ~1400000 мкс, визуальная alpha достигает 1.0 раньше следующего snapshot, и движение замирает. GUI остаётся 60 FPS.

## Изменение

- `godot/scripts/ui_source_motion_interpolator.gd`: display-only duration = 115% последнего **измеренного** интервала получения двух реальных snapshots, min 50ms, max 3500ms вместо 650ms. Это небольшой запас от jitter и адаптация к late ticks. **Никаких новых source ticks, интерполяции дальше подтверждённой curr position, изменения N9/N39/N38/Clock/AI**. Если источник задержится дольше 3.5 сек, анимация честно остановится до нового canonical state.
- `godot/tests/p2_perf_e_visual_interpolation_check.gd`: негативный регресс на 1.4s interval, отсутствие прежней остановки на 650ms, clamps, initial/reversed timestamp.
- `.github/workflows/p2-perf-e-visual-motion-short.yml`: повторно запускает короткий smoke при изменениях этих файлов.

Коммиты: код `3dafc6c2`, тест `1ce0c105`, CI конфигурация `024b1ee6`.

**CI PASS**: https://github.com/Mefits/Living-Sector/actions/runs/43855424760, Godot 4.7.2 Linux: full import/parser, targeted motion regression + 32 source ticks with worker GUI. Не путать с Windows FPS.

## Нерешённая задача

Рост стоимости authoritative sim к tick2300 остаётся. Visual tween — маскирующая UI коррекция. Дальше приоритет: same-seed late-tick profiling of N158 phases / N39 deep World copies / ledger receipts / market & ship hotpaths, чтобы убрать рост `sim_ms` в 10x. До измерения не увеличивать max thread count и не выдумывать перемещения. Windows после Pull + F5 проверить x16 early/late: продолжительность freeze и реальный tick/sec.

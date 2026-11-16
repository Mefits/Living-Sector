# PERF E — проверенный real Thread N158 + измеренный узкий профиль до тика 601

Дата: 2026-11-16. Общая ветка: `integration/perf-astra-5-workers-20261116`, PR #262. Никаких merge.

## Что реализовано в коде

- `godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd` — отдельный `Thread.start`, внутри которого создаётся **единственный** authoritative N158 Runner и N39/N9. Запросы управления, step, checkpoint, N38 save/load/restore идут через detached FIFO; UI не получает живую ссылку на Runner, World, Ledger. После плохого restore владелец замораживается. Это изолированный opt-in модуль, **НЕ подключён к main.gd**.
- `godot/tests/p2_perf_e_real_owner_n158_parity_check.gd` — настоящий direct N158 vs worker на одном frozen Rust seed, 24 ships, шесть оплаченных тиков, полное сравнение checkpoint, N38 save/load, проверка допустимого exact JSON integer→float, отказ corrupted restore, запрет ссылок на живые объекты.
- `godot/scripts/sim/phase2/n158_timed_phase_probe.gd` — прозрачный изолированный subclass N158 с замерами всех фаз, без вмешательства в исходные механики.
- `godot/tests/p2_perf_e_601_tick_phase_hotspots.gd` — ограниченный профиль реальной экономики до tick601 без поддельных перевозок, сохранения/баланса в тесте не изменяются.
- Ограниченные CI: `.github/workflows/p2-perf-262-owner-short.yml` (10 мин), `.github/workflows/p2-perf-262-601-tick-phase.yml` (12 мин).

## Реальные результаты

**Real worker vs direct: PASS**, Godot 4.7.2 Linux, Actions https://github.com/Mefits/Living-Sector/actions/runs/43837877453 . Исходные два запуска нашли неправильное требование строгого Variant TYPE_INT при JSON N38 (у некоторых счётчиков разрешено точное преобразование TYPE_INT→TYPE_FLOAT); исправили oracle, **не меняли SaveState или финансовые правила**. 6 ticks + exact authoritative checkpoint + N38 disk restart + corrupted restore negative passed. Это НЕ подтверждение FPS, worker пока не подключён к SceneTree.

**Источник до tick601: PASS**, Godot 4.7.2 Linux, Actions https://github.com/Mefits/Living-Sector/actions/runs/43838502237 , LS_PROFILE_NATIVE_PHASES=1, speed ×8 / TPS 8, original clean source seed. 601 ticks за 113.204 s измеренного tick CPU. Измерение содержит overhead instrumentation и отличается от Windows F5.

| Окно/фаза | Результат |
| --- | ---: |
| Последние 100 тиков (501–600): среднее | 259.29 ms/tick |
| Последние 100 тиков (501–600): p95 | 318.32 ms/tick |
| 501–600 ships: delta cumulative | ~111.53 ms/tick |
| 501–600 factions: delta cumulative | ~66.53 ms/tick |
| 501–600 markets: delta cumulative | ~59.98 ms/tick |
| 501–600 populations: delta cumulative | ~6.30 ms/tick |
| N39 `deep:L129` World snapshot over 600 ticks | 4 995 calls / 18.952 s |
| N39 `deep:L129` over ticks 501–600 | 836 calls / 4.327 s (~43.27 ms/tick) |

Фазы inclusive, плюс timers/harness; не суммировать их как гарантированную общую картину CPU. User Windows F5 при tick601: FPS 3, frame p95 504.2 ms, sim+signals 485.6 ms, UI 9.0 ms. Сравнение Linux TPS ≠ Windows FPS. Проблема отзывчивости НЕ исправлена.

## Следующий приоритет

1. **E:** Подключить к `godot/scripts/main.gd` безопасную production-real worker ownership boundary: N158 создаётся на worker и только worker мутирует World; GUI читает detached committed FrameView. Нельзя просто перенести `_runner.advance_frame` в поток, пока `_model`/observer/save/load/controls читают live runner и пока нет точного 420/N38 restart паритета. Начать за opt-in флагом, с реальными контролами и render snapshot; принимать только после GUI Windows F5 vs old baseline и отсутствия torn frames. Единственный источник истины N158/N39/N9.
2. **A и C:** Корабли на tick501–600 ~111.5 ms/tick и многократные `production.world_snapshot()` (`deep:L129`) ~43.3 ms/tick: заняться именно вызовами с гарантией отсутствия intervening N39 writes, без раздачи mutable alias. Проверить same-seed exact parity + negative cases, измерять выигрыш.
3. **D:** Фракции ~66.5 ms/tick, markets ~60 ms/tick: профилировать реальные N100/Head/N150 callsites и убрать только доказанные повторные вычисления.
4. Никаких 420/900/10k CI на каждый коммит; GitHub Actions >35 минут закрываются; короткий parser/2tick smoke уже PASS. Полный N38 restart/negative перед включением default backend.

Текущий результат: **реальный Thread N158 и phase-profile внесены и протестированы; Windows FPS пока без улучшения**.

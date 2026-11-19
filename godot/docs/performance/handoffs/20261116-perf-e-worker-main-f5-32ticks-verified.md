# Living Sector · PERF E — настоящий worker подключён к F5 за экспериментальным флагом

Дата: 2026-11-16. Репозиторий `Mefits/Living-Sector`. Только общая ветка `integration/perf-astra-5-workers-20261116`, draft PR #262. Frozen Rust 0.6.7 — эталон логики; баланс/AI/деньги/грузы и source cadence не менялись.

## Реальный код

- `godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd`: один authoritative N158/N39/N9/Clock создаётся и изменяется на `Thread`. Добавлена ограниченная передача `frame(delta)`; ответы включают ТОЛЬКО detached снимки завершённого мира, орбит, кораблей, сводки и (когда нужно наблюдателю) N38-фрейма. Никаких живых объектов UI не получает. FIFO сериализует pause/resume/step/speed/save/load на границе тиков. Не допускаются плохие дельты, live references и произвольные пути сохранений.
- `godot/scripts/main.gd`: реальный экспериментальный запуск F5 через `LS_N158_WORKER_GUI=1` или `--p2-worker-gui`. `_process` больше **не вызывает** `_runner.advance_frame` в этом режиме: передаёт bounded elapsed только в owner FIFO и обновляет UI detached данными. Карта использует независимый read-only `WorldModel` из исходного seed и authoritative orbital snapshots после commit. Observer, status, ships, навигация, pause/step/speed, save/load выведены из shared live Runner. Ручные непротоколированные корабельные действия заблокированы. Старый прямой режим используется без флага по умолчанию.
- Отдельный worker save slot: `user://saves/galaxy-067-p2-worker-experimental.json`. Обычный `galaxy-067-p2-integration.json` не перезаписывается в эксперименте.
- `godot/run-worker-gui-windows.cmd`: однокликовый запуск Godot 4.7.2 в worker-режиме. Если автоматический поиск exe неудачен, Godot.exe можно перетащить на .cmd.
- `godot/tests/p2_perf_e_real_owner_n158_parity_check.gd`: direct vs thread exact checkpoint после 9 paid ticks + 5 реальных frame delta + N38 restart + reject corrupt checkpoint.
- `main.gd` opt-in headless checks: `--p2-worker-gui-check` (2 тика, карта, N38), `--p2-worker-gui-run-check` (настоящие 32 тика и параллельная отзывчивость SceneTree).
- `.github/workflows/p2-perf-262-worker-gui-short.yml`: bounded GitHub Actions до 10 минут, без 420/900/10k long soak.

## Проверенные результаты

CI: **PASS**, Godot **4.7.2 Linux**, https://github.com/Mefits/Living-Sector/actions/runs/43842795997

1. Parser/import all scripts: PASS.
2. Real F5 worker GUI, two paid ticks, detached projection, system/sector navigation, N38 save/load: PASS; zero SCRIPT ERROR.
3. Direct N158 vs real worker, 9 paid ticks and 5 variable frame deltas: full authoritative checkpoint parity PASS. Corrupted restore freezes owner PASS; N38 exact save/restore PASS.
4. Original **default F5** two paid ticks, N38 and scene navigation: PASS; original production backend not changed.
5. Worker F5 live run: **32 authentic source ticks in 4.0 s**, **576 GUI frames**, main-thread `_process` CPU **p95 1.65 ms**; no SCRIPT ERROR. Это headless Linux, без GPU. Не называть 576/4 = 144 пользовательскими Windows FPS.

Ранее к tick601, Linux x8 with source instrumentation: ships ~111.5 ms/tick, factions ~66.5, markets ~60, 4995 `deep:L129` World copies on 600 ticks (~43.3 ms/tick over last 100). CI: https://github.com/Mefits/Living-Sector/actions/runs/43838502237 . Показания **Windows прежнего режима на t601**: FPS 3, frame p95 504.2 ms, sim+signals 485.6 ms, UI 9.0 ms.

## Статус приёмки

**Реальное подключение opt-in worker сделано и проверено.** Пока **НЕ включено по умолчанию**: нужно проверить GUI Windows F5 в тех же условиях (особенно 24 ships, ×8, ×16, tick600, observer open/closed, pause/step, N38 load/save, map navigation) и полное 420/restart deterministic parity для экспериментального GUI. Нет подтверждённого Windows FPS; не обещать 60 FPS.

Следующие независимые изменения PERF A/C/D направлять строго на измеренные большие hotpaths, не на микрокеши без профиля. Не merge в integration до Windows acceptance.

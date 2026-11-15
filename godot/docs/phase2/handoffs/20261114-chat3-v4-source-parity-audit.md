# Чат №3 / В4 — итоговый аудит исходников Rust → Godot и оставшиеся SOURCE-GAP

14.11.2026 · общий PR #249 · `integration/godot-phase2-unified-20261113`

## Выполнено

1. Проверена **живая** цепочка `native/crates/sim_server/src/engine.rs` → `godot/scripts/sim/tick_runner.gd` → `godot/scripts/sim/phase1/n39_native_production_tick_runner.gd` → `godot/scripts/sim/phase2/n158_production_runtime.gd` → единый `n39_native_world_production.gd` / N9 / N104 / N38. Это source-connectivity, **не** проверка исполнения.
2. Проверены original `native/priv/galaxy/data/tuning.json` и Rust `WorldTuning::default`. У Galaxy отключены `auto_replace_retired_ships=false` и `regenerate_body_resources=false`; вопреки Rust legacy default `true`, их **не нужно включать в Godot**. Не путать с незавершённым N154 реальным созданием кораблей.
3. Конкретно выявлен **активный** Rust N21 `tick_dock_queue_advance` и FIFO путь из `native/crates/sim_server/src/engine/apply.rs` (source линии ~395–585, 752+): в Godot `docking_registry.gd` при полном доке выдаёт `no_available_dock`, очереди нет, в N158 фаза `dock_queue` остаётся без Apply. Отмечено как P0 blocker A. Не создавать отдельный DockingRegistry с очередью вне канонического N39.
4. Сверены source-only блоки текущих параллельных чатов: Chat1 N80 exploration/mining source stage RELEASED, но live N158 API не установлен; Chat2 B4 N92 aftercare в работе и не подтверждён actual N39 apply. Требуется перепроверить новые leases перед следующими изменениями.
5. Найден diagnostic gap: в N158 `phase == "crisis"` реально выполняется, но `implemented_phases()` не сообщает `crisis`. Это не сбой выполнения фазы, однако ложная диагностика; общий N158 сейчас зарезервирован Chat2 B4, **не редактировался**.
6. Проверены экспортные исходники: `.github/workflows/p2-unified-godot-smoke.yml`, `p2-windows-release.yml`, `godot/scripts/phase2_package_windows.sh`, `godot/export_presets.cfg`, `NativeData.load_current_world()`. Один Windows ZIP готовится на Godot 4.7.2, seed копируется из Rust Galaxy и проверяется по SHA256. Это существует как source pipeline, но **не исполнялось**.

## Артефакты этой итерации

- `godot/docs/phase2/P2_V4_FINAL_ACCEPTANCE_MATRIX_RU.md` (`51ecef7`) — полная таблица A/Б/В/Г, Rust→Godot phase inventory, классификация source-wired vs source-only, P0–P2 остатки, единая acceptance процедура **после** завершения переноса.
- `godot/tools/p2_v4_source_gate.py` (`6225f95`) — **один** автономный offline read-only source verifier на stdlib Python. Сопоставляет порядок фаз, источники World/N9/N104/N38, frozen tuning false, market/crisis/colony/Head entry points, проверяет недостающие N21 FIFO/N80/N92 и false `implemented_phases`, сверяет preload targets. Опционально `--json --require-complete`. **Авторский исходник, НЕ запускался; ни исполнение Rust/Godot, ни тест, ни доказательство PASS.**

## Актуальные ограничения

**V4_SOURCE_AUDIT_READY / SOURCE_INTEGRATION_INCOMPLETE / RUNTIME_UNVERIFIED**. GitHub статические чтения + source diff, без Godot/parser/F5/Windows/Actions. В P2 не менялись код экономики, темп тиков, рынок, ресурсные формулы, баланс и AI. Нет общего `SOURCE_INTEGRATION_COMPLETE`, пока P0 N21, P1 N80/N92 и diagnostic P2 phase inventory не устранены в исходниках. Нельзя считать готовность по количеству коммитов (более 1000) или отдельным адаптерам.

## Передача задач, безопасный порядок

1. **Чат №1 (флот, после собственной leases):** оригинальная N21 FIFO queue в том же N39 `FacilityStorage` + N9 fees/receipt, N158 source `dock_queue` tick независимо от N140/LOD; контроль stale/insolvent heads, N38 queue recovery. Никаких бесплатных dock slots или teleport.
2. **Чат №1 / N80:** actual N80 exploration/mining goals and N146 execution only through существующий планировщик/World. При наличии адаптера без N158 Apply это ещё source-only. Сначала HEAD/leases.
3. **Чат №2 / Б4:** N92 real needs/goals → N134/N100/N121 → N39 owned Apply and resource/receipt lifecycle, без нового баланса; release shared N39/N158 сразу после.
4. **Чат №3 / после Б4:** маленькая диагностическая поправка `implemented_phases()` для реально wired `crisis` и остальных действительно подключённых фаз. Не менять существующую семантику.
5. **В4/Г только ПОСЛЕ source closure:** запустить `python3 godot/tools/p2_v4_source_gate.py --require-complete --json` как структурный preflight; затем один согласованный Godot 4.7.2 compile+end-to-end A/Б/В/Г и Windows ZIP/boot. Пользователь отдельно просил **не запускать промежуточные tests/Actions** и не начинать его пакет механических/балансных правок до полного переноса.

### Проверка полноты отчёта

Отчёт НЕ обещает «весь Rust перенесён». Сетевые Rust API/WS/SQLite worker-слои не следует механически клонировать в offline Godot: сохранять **функциональные эффекты, кошельки, события и persistence**, а не копировать серверную архитектуру. Критическими считаются только доказанные игровые разрывы.

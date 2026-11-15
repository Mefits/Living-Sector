# Living Sector P2 — Чат №3 В2 / исходный Rust Bundle(S) кризисы: полный runtime source wiring

Дата: 2026-11-14 · PR #249 · общая ветка `integration/godot-phase2-unified-20261113`

## Эталон Rust и порядок фаз

`native/crates/sim_server/src/engine.rs::scan_crisis_events` (оригинальные строки 789–843) вызывается после `markets` и перед `apply2` в общем исходном цикле `TickRunner.NATIVE_PHASE_ORDER`. `WorldTuning` default: рынок shortage ≥200 — `market_crisis`, recovery ≤50 — `market_recovered`; `FacilityOperations.condition <0.3` — `facility_starving`, >0.5 — `facility_recovered`. Пороговые флаги `MarketHistory.crisis_notified` и `FacilityOperations.starving_notified` препятствуют повторному событию при удержании условия и сохраняются на диске.

**Важно:** это НЕ `strategy/director.rs::environmental_events` (в исходном active engine нет подтверждённого вызова аварий). Случайный ущерб/аварии, мораль, цены, кредиты, добыча и другие балансы не изменены.

## Реальное подключение (источники/коммиты)

Ранее чатом №3 были сделаны pure helper `unified_native_crisis_events.gd`, N150 market-history flags, read-only Observer. Эта итерация закрывает зависимость от общей ветки:

- `197c2a5`: новый `godot/scripts/sim/phase2/unified_native_crisis_phase.gd`. После подтверждённого N150 Market Apply сравнивает pre/post-market snapshots и exact staged `crisis_events`: запрещает выдуманный или повторный market event, сверяет оригинальные shortage counters, историю и гистерезис. В составе того же кризисного предложения рассчитывает строго исходные facility flag transitions. `expected_facility_flag_world` — чистый preflight для N39, не дополнительный владелец World.
- `c4eeeb9`: существующий `unified_native_crisis_events.gd` пропускает legacy FacilityIdentity без `FacilityOperations.condition`, как Rust ECS join; не выдумывает компонент.
- `0904d68`: `godot/scripts/sim/phase1/n39_native_world_schema.gd` валидирует optional bool `starving_notified` на реальной facility и bool map `history.crisis_notified` на рынке. Legacy rows без новых полей совместимы.
- `5a21667`: `godot/scripts/sim/phase1/n39_native_world_production.gd::apply_native_crisis_phase` — **единственная точка записи facility warning flags**. Повторно сверяет исходные market event proofs против уже записанного N150 MarketHistory, перечитывает actual `FacilityOperations.condition/starving_notified` и отвергает stale/replayed proposals. При изменениях флага клонирует/валидирует текущий N39 World, сверяет все авторитетные N9 счета с `Schema.accounts`, затем единожды коммитит `_world`. Возвращает упорядоченные market-then-facility events только при успехе; не эмитит события при отказе.
- `0a973b7`: `godot/scripts/sim/phase2/n158_production_runtime.gd`: **активная** `phase == "crisis"` в существующем N1/N158 TickRunner. N150 market stage сохраняет premarket World, аттестует настоящий N39 Market commit и строит transient crisis proposal до N152; на следующей фазе `crisis` вызывает единственный N39 Apply. Сразу после успеха отправляет исходные переходы через уже существующий `scheduled_event_due` сигнал; **не создаёт второй EventQueue, отдельный тик, кошелёк или постоянный список событий**. Стадия очищается после commit/restore, состояние ошибки замораживает тик через исходный failure path.
- `5076659`: существующая компактная панель `observer_panel.gd` показывает фактические market/facility warning transition counts за последний тик, помимо уже сохранённых active warning counts; без нового окна/системы.
- `dd1fd60` + `2bafe23`: отложенная pure regression `p2_native_crisis_atomic_phase_check.gd` тестирует 200/50 и строгое <0.3/>0.5, реальную сохранность, no-repeat, отрицательные/фальшивые events, аттестацию market commit, stage output не меняет credits/stock/hold и legacy facility без Operations.
- `867787a`: отложенный сквозной `p2_native_crisis_n158_runtime_check.gd`. Реальный frozen native seed, изолированный test-runner с установленными порогами, `N158` шаг 1 → наблюдение двух сигналов и N39 флагов, тик 2 → suppression duplicate, N38 save/load → тик 3 без повторного уведомления.

## Статус и ограничения

**RUST_CRISIS_SOURCE_WIRED / CODE_UNVERIFIED**. Исходный код В2 теперь содержит полноценный путь `N150 MarketPhase → N39 MarketHistory → N1 crisis phase → N39 FacilityOperations → N1 signal/Observer → N38 save/restore`. Изменённые 8 GDScripts перечитаны из актуального GitHub HEAD: сбалансированы `[]{}()`, кавычки, нулевые символы отсутствуют, строки кончаются newline. Это **только статическая проверка**; исходные функции, event delivery, сериализация и фактическое поведение **не выполнялись**.

Пользователь просил не запускать промежуточные Godot/Windows/F5, тесты или GitHub Actions до завершения всего Rust → Godot переноса. **Godot runtime / Actions = 0, PASS не заявлен**. Не объединять в отдельный PR, всё уже в общей PR #249.

## Конкурентная разработка / source ownership

Сначала Chat1 N108 Gate Pair владел N39/N158/Schema. Работу там **не начинал**. После получения `RELEASED` и проверки отсутствия других новых claims расширил собственную lease `20261114-chat3-v2-crisis-atomic-stage.json` (commit `b4a154f`), внёс изменения только в кризисных секциях; все N108 Gate Pair и Chat2 colony B3 исходники сохранены. Перед правкой каждого файла проверял актуальный SHA; конфликтов записи на общих файлах в этом блоке не было.

## Следующая работа

1. После завершения оставшихся исходных работ всех трёх чатов выполнить общую source-проверку фазы и один финальный Godot acceptance. Запустить `godot/tests/p2_native_crisis_atomic_phase_check.gd`, `p2_native_crisis_events_source_check.gd`, `p2_native_crisis_observer_projection_check.gd`, `p2_native_crisis_n158_runtime_check.gd` в едином checkpoint; если есть parser error — исправить по реальному результату.
2. Проверить события для изменяющегося shortage при 200/50 и facility condition при 0.3/0.5, отсутствие повторов на тиках 2–3 после N38 roundtrip, один владелец World/N9, no unintended financial/stock changes.
3. Чат №3 после этого может брать В3 или В4: итоговый статический source audit всего переноса и общий план Windows/Godot/F5, не менять баланс.

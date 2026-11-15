# Living Sector · Пять автономных смен оптимизации Астры (16.11.2026)

> Рабочий координационный документ. Не является доказательством ускорения. Обновлять при каждом крупном проверенном блоке. Источник: независимый `Living-Sector-Performance-Architecture-Audit-RU(2).md` (15.11), страница «Оптимизация» https://www.tldraw.com/f/Dzo-huxLVMxka2COuru0w , реальные Windows профили и PR #250–#261.

## Задача и область работ

Устранить блокировки UI и рост стоимости экономических тиков **без переписывания Living Sector**, без фальшивой активности кораблей, изменения баланса/ИИ/скоростей, отключения финансовых защит, новых источников истины или ослабления N38. Frozen Rust 0.6.7 — эталон поведения. Игрок и мандаты не входят в этот этап. Детерминированные N1/N158 phase/cadence/BT/RNG, контракты/доки/оплаченные товары, счета N9, полный World checkpoint и N38 должны сохранять смысл.

**Рабочая ветка всех пяти:** `integration/perf-astra-5-workers-20261116`, ответвлена от `integration/godot-phase2-unified-20261113` @ `4c315dc9`. ОДИН общий draft PR из этой ветки обратно в integration; не создавать пять PR на сотни микроправок, не менять `integration/godot-phase2-unified-20261113` и `main` напрямую. **PR #261** (`feature/perf-astra-reconstruction-20261115`) остаётся отдельным экспериментом: до успешного Windows CI/проверки паритета не переносить механически весь patch и не объявлять worker подключённым. Включать доказанно полезные части выборочно, по файлу и со сравнением.

### Уже внесено в integration (НЕ повторять)

- #250: N21 квадратичный receipt snapshot, N129 wallet repair, N84 ship copy; #251 N39 bounded ship copy, balances-only N9 reads.
- #253 N9 trusted fork и N21 old-receipt guard; #254 route cache; #255 N9 append-only/sharded journal; #256 N39 market/dock owned stages.
- #257 локальные валидаторы/write-sets; #258 N153 индексы/события; #259 UI FPS overlay/coalescing; #260 N158/N39 projection/profiler (все PR уже merged в integration).
- #252 N39 operating-world COW **отклонён как недоказавший выигрыша** — не восстанавливать без новых замеров.
- #261 draft: N39 limited lifecycle/research stages и N91/N143 no-op, balances reads, experimental isolated N158 worker; **не подключён к main.gd**. Windows Actions #43762574707 для парсинга/16/420 тиков. Сначала узнать фактический результат.
- Факт из Windows до #261: при 24 кораблях ×8 tick165 FPS ~6, ×16 tick277 FPS ~3; UI p95 2–3 ms, основная задержка в синхронном `main._process → N158.advance_frame`. Уменьшение копий может помочь TPS, но не гарантирует плавный UI.

## Общее правило одного рабочего запуска

1. Прочитать **этот документ целиком**, актуальные HEAD, PR #261, Actions, `godot/docs/phase2/handoffs/`, свежие perf handoffs и leases; не считать устаревшие описания фактическим состоянием. Проверить изменения других четырёх смен прежде, чем писать.
2. Сохранять **свой фиксированный домен** ниже. Перед общим файлом поставить согласованный claim в `godot/docs/performance/leases/` (уникальный файл с owner/path/HEAD/time; не перезаписывать чужие), убедиться, что нет действующего claim. При конфликте выбрать независимый модуль или тест, не ждать человека.
3. Выполнить **реальную крупную кодовую итерацию** (логическая функция + targeted tests + доказательства) и сохранить commit в единой perf branch с ожидаемым blob SHA/CAS; при конфликте reread и перенести изменение, без force-push.
4. Воспользоваться Godot 4.7.2, если доступен. Если нет, запускать статические проверки и честно помечать CODE_UNVERIFIED. Никогда не объявлять PASS из текста теста. Проверять exit code, отсутствующие scripts/ресурсы и реальные значения.
5. В `godot/docs/performance/handoffs/YYYYMMDD-HHMM-<A|B|C|D|E>.md`: HEAD до/после, modified files, измерение baseline vs candidate на том же коде/условиях, PASS/FAIL/непроверено, инварианты, технический долг, следующий свободный блок. Закрыть lease. Не расходовать итерацию только на отчёт/реорганизацию.
6. НЕ запускать GitHub Actions на каждую правку и НЕ трогать триггеры workflows; использовать существующий совместный checkpoint после существенного законченного блока. Сначала прочитать логи #43762574707. Не запрашивать ручной PowerShell у пользователя — он уже потратил время на ошибки парсера.
7. Для каждого рефакторинга: сравнение полного authoritative checkpoint (World+N9+contract/cargo/fuel/BT/RNG/clock) и N38 restart360; negative tests на дубликат operation, подделку/удаление receipts, insufficient funds/stock, двойную стыковку/контракт, partial failure. Сохранить deterministic tie-break и порядок source commits. Старый Schema oracle остаётся в сравнительных тестах.
8. Никаких незавершённых staged изменений в UI, поддельных рейсов, уменьшения SEARCH_BUDGET 350/depth 12, временного отключения guards, изменения математических формул/cadence, второй authority World/ledger/runner, «оптимизации» за счёт сокращения AI/механик.

## Пять независимых рабочих направлений и чёткое владение файлами

### A · N39 transactions / validators / World ownership

**Основные файлы:** `godot/scripts/sim/phase1/n39_native_world_production.gd`, `n39_native_world_schema.gd`, новые `n39_*validator*.gd` и свои `godot/tests/p2_perf_a_*.gd`. **НЕ редактировать** `credit_ledger.gd`, `save_state.gd`, `main.gd`, `n158_production_runtime.gd` без согласованного lease.

**Остаток рекомендаций:** убрать ненужные полные World stage/Schema на честных no-op и узких write sets, **только если A/B экономит реальное время**; проверить bounded lifecycle (facilities/markets/populations), N91 empty assignments и N143 research heads/paid shifts из #261; локальные versioned validators touched domains плюс cross-domain invariant checking; не заменять полную валидацию до oracle evidence. Population `Schema.accounts` hoist — **проверить существование, не дублировать**. Инкрементальные доковые/строительные provenance aggregates с проверкой по полному оригиналу. Диагностика N129 tick825, если ещё проявляется в актуальной ветке: account IDs/expected vs actual/source transfer, не bypass. Долгосрочно — bounded data-oriented hot store для N39 при измеримой пользе.

**Гейт:** true 420/900 + N38 restart360 + invariants, negative alias/rollback; same-build force-legacy vs optimized с одинаковым seed, профайлером и фазовыми окнами. No loss of receipts or money.

### B · N9 Ledger / append-only history / N38 persistence

**Основные файлы:** `godot/scripts/sim/economy/credit_ledger.gd`, `godot/scripts/sim/save_state.gd`, `godot/scripts/sim/phase2/unified_native_save_roundtrip_guard.gd`, новые finance/archive модули и `godot/tests/p2_perf_b_*.gd`. **НЕ редактировать N39/world schema, main/worker/ships** без lease и согласованного контракта с A/E.

**Остаток рекомендаций:** проверить остаточные deep-copy N9 per payment; owned transaction overlay по изменённым кошелькам/new receipts/operation IDs (идемпотентность, provenance lookup, append-only); dock/construction receipts summation by incremental proven aggregates с full-audit oracle; snapshot только для save/restart/диагностики. Инструментация encoded save bytes, limit 16 MiB; затем **условная** N38 vNext segmented authenticated archive/manifest/atomic pending/bak, backward compatibility, old receipt references, exact f64/currency and replay. Не просто увеличить лимит.

**Гейт:** old/new ledger balance/receipt sequences identical, exact N38 roundtrip and tamper negatives, reproducible save size growth vs receipt count; no active World's shared mutable alias.

### C · Fleet, contracts, route graph, hot ship indices

**Основные файлы:** `godot/scripts/sim/phase2/unified_ship_phase.gd`, `unified_ship_ai_execution.gd`, `unified_n140_*.gd`, `unified_n153_contract_dispatch.gd`, `godot/scripts/sim/route_graph.gd`, ship helpers, `godot/tests/p2_perf_c_*.gd`. **НЕ редактировать N39, N9, N158, main/UI** без согласованного lease.

**Остаток рекомендаций:** убрать повторные N140 agent-map/ships, N14 gate, N84 BT/world, AI fleet/row copies с read-only/owned boundary и tests на sleeping/travel/service/refit/recovery; проверить реальную N140 LOD/cursor и сохранение решений. Продолжить #254/#258 только измеренно: indexed eligible ships & available contracts, versioned graph routes, dock occupancy, stable tie-break, invalidation on gate/ship/contract changes. Декомпозиция C×S и Dijkstra O(V²+E): heap/native **только после профиля на большом валидном графе**. Для 100/500/2000+ ships нагрузочные fixtures должны иметь уникальные ID/кошельки/реальные оплаченные контракты, не фиктивные перемещения. Data-oriented packed ship kernel как эксперимент за отдельным флагом и strict replay, не production по умолчанию.

**Гейт:** route cached/uncached oracle; exact decisions/contract/order/cargo/fuel/BT parity; 24/100/500 validity and p95 in active paid economy, no fake departures.

### D · Stations / markets / Head / events and cadence

**Основные файлы:** `godot/scripts/sim/phase2/unified_native_station_administration_phase.gd`, `unified_market_phase.gd`, `unified_native_hybrid_planning.gd`, `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`, `godot/scripts/sim/event_queue.gd`, supporting admin/AI/market modules, `godot/tests/p2_perf_d_*.gd`. **НЕ редактировать N39/N9/N158/main/UI** без согласованного lease.

**Остаток рекомендаций:** index (faction,location) facilities/populations, stable ordered facility roster with versioned invalidation, Head faction read views, remove redundant market DTO materializations, avoid repeated full scans, read-only projections. Event queue `take_due` O(P·E) → bucket by due_tick/phase or ordered heap **only if benchmark shows benefit**; preserve `(due_tick, phase, entity_id, sequence)`. Retain source administration/head/finance/migration cadence, market trend and all planner search budget/decision semantics. Compare original per-faction plans, market prices, jobs, source offers, receipts, and research.

**Гейт:** indexed vs naive oracle on install/remove/move/ownership/gate/market changes; 420/900 and after long history, full decisions/price/ledger parity; actual measured ticks for facilities/markets/factions/event queue.

### E · Worker-owned N158 + immutable UI FrameView + benchmark acceptance

**Основные файлы:** `godot/scripts/main.gd`, `godot/scripts/sim/phase2/n158_production_runtime.gd` (with lease), new `n158_threaded_runner_owner.gd` / `frame_view*.gd`, `godot/scripts/*view*.gd` (UI), profiler/check harness and `godot/tests/p2_perf_e_*.gd`. **НЕ редактировать N39, N9, N38, N153, market/head modules** без согласованного lease.

**Остаток рекомендаций:** забрать только проверенные части #261. Отдельный worker — единственный владелец authoritative N158/N39, UI не читает live mutable World; command queue pause/resume/step/speed/checkpoint/save/load и bounded immutable detached completed FrameView. **Реально подключить к `main.gd`**, Observer/fleet/map/status, retire synchronous `_runner.advance_frame(delta)` на UI thread. Политика отставания/ускорения без пропуска логических тиков, save только на завершённой границе, freeze/error diagnostics при partial failure; deterministic replay при разных frame rates/worker delays. Добавить on/off backend toggle для controlled A/B, сначала prototype и отложенный switch после acceptance. UI projection per committed tick + only visible/dirty panels, не повторять #259 overlay.

**Отдельная обязанность по измерениям:** единый bounded benchmarking protocol: чистый seed 24 и валидные 100/500/2000 ships (когда C предоставит fixture), CPU avg/p50/p95/p99/phase callsite/copy/Schema/N9/allocated bytes/RSS/GUI frame time; 420/900, далее 1k и 10k после N129 and N38 gates, pause/×1/×8/×16, observer shown/hidden, restart360/1k/10k. Сравнивать одинаковые Windows Godot 4.7.2 builds/speeds/seed/flags, отделять headless TPS от FPS. Позже исследовать deterministic read-compute parallelism 2 workers only после стабильного single-owner, компактные native kernels лишь при подтверждённом hotspot.

**Гейт:** сначала Windows Actions #43762574707 (parse → 16 worker → N39 420 → worker 420) и точные логи. Потом headless 420 parity direct vs threaded, N38 restart, GUI F5/run FPS baseline vs worker/paused and no torn frames, сохранение N9/BT/RNG/cargo/contract. Worker prototype без UI wiring **не считать FPS fix**.

## Общий backlog, все пункты аудита распределены

- I: N21 snapshot/PR250, accounts hoist, narrow accessors, UI projection, metrics — отметить уже внесённое и проверять без дублирования (A/B/E).
- II-A: N9 append-only + stage overlays + invariant transaction + provenance (B, вызовы N39 от A).
- II-B: bounded owned write sets, local validators, versions & delta (A; владение N39 только A).
- II-C: ship/contract/dock/route caches (C), station/faction/market rosters (D).
- II-D: responsive worker scheduler, committed presentation/queue (E).
- III: packed hot stores (A/C/D after 500), native kernel A/B experiment and API marshalling (C/E, only measured), parallel deterministic read-compute (E, only after serial worker), N38 segmented archive (B).
- Long-run/perf evidence: fixture 24/100/500/2000/10000 (C produces data; E runs); N129 tick825 if reproduced (A with B), N38 restart and save bytes (B/E); event queue (D). No speculative claim 10k PASS.

## Integrating evidence and stopping conditions

Every change must give one of: measured improvement with invariant parity, safety invariant improvement with quantified overhead, or a **documented rejected experiment**. If no measurable benefit and no necessary ownership boundary: revert, record (as with #252). A long-run timeout ≠ PASS. Native/Rust/GDExtension conversion requires an end-to-end win including marshalling and exact replay; not permitted as default before proof. Final acceptance: responsive UI during 24-ship real simulation, stable per-tick cost versus history after bounded 1k/10k, no economy/AI rule differences, native save/restart/rollback, Windows packaged evidence. **No automatic merge into integration** — shared draft PR needs explicit review.

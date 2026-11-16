# Living Sector · Пять автономных смен оптимизации Астры (16.11.2026)

## 🚨 НЕ ДУБЛИРОВАТЬ ДВА ФИКСА АСТРЫ (17.11.2026)

PR #262 УЖЕ содержит 99ab25e9 (N9 WeakRef, N152 no-op, N91 receipt proof, N39 engineer ship-only) и 1676db61 (8 N158 world_snapshot readsites заменены на detached N39 projections; 27→19 статических callsites). НЕ повторять эти изменения, НЕ писать ещё раз те же read projections. Новый короткий HEAD CI #43972442164 успешно проверил оба пакета: 500 реальных тиков, worker+N38, targeted WeakRef/projections, 160-тактовый legacy-vs-owned A/B с 5/5 точных checkpoint hashes. Поздние 900/2600 и Windows memory soak остаются НЕПРОВЕРЕННЫМИ. E отвечает за дальнейший профиль; остальные смены ищут новые узкие места.

Статический аудит: 1) профилировщики N39/N158 бесконечно накапливают samples только в opt-in режиме; 2) N152 все еще копирует историю ContractBoard на no-op tick; 3) N39 L196 deep World per paid tick. Подробности и границы уверенности: [17 November checkpoint](checkpoints/20261117-two-astra-fixes-independent-audit-ru.md). tldraw: https://www.tldraw.com/f/Dzo-huxLVMxka2COuru0w → Оптимизация.

## СРОЧНЫЙ ПРИОРИТЕТ: позднетиковая деградация 137→839 мс (16.11, обновление задач)

**Перекрывает любые устаревшие task examples, перечисленные ниже.** Цель — измеренное ускорение оплаченных тиков при сохранении всего source behavior, не новые доки, FIFO safety helpers, UI/worker или дополнительные InterpPos костыли.

Реальный CI профилирования: https://github.com/Mefits/Living-Sector/actions/runs/43856475886 — 8-минутный bounded прогон, чистый seed Rust, Godot 4.7.2 Linux, `LS_PROFILE_NATIVE_PHASES=1`: последние 100 paid ticks `tick100 avg 137ms`, `tick300 avg 284.55ms`, `tick600 avg 469.61ms`, `tick900 avg 786.21ms`, `tick969 avg 839.31ms`. **До tick2600 не дошёл**: wall budget 480 s. Windows worker: ~147ms/request tick585 → ~1430ms/request tick2329, UI ~60FPS; request elapsed НЕ приравнивать автоматически 1 paid tick. Сопоставлять same seed/phase/profile и counters, не Windows FPS с Linux.

**Фиксированное разделение направлений (автозадачи A–E уже обновлены):**

| Исполнитель | Фактический узкий путь | Порядок работы |
| --- | --- | --- |
| **A — N39 World** | `deep:L129` ~2929 World snapshots / 34.66s на tick601–900 | Найти повторный snapshot с доказанным владением / отсутствие intervening mutation, исправить фактический caller в A-owned owned stages; full Schema oracle, alias/rollback |
| **C — ships+dock_queue** | ships 117.65s и dock_queue 26.49s за 300 ticks (601–900) | Профиль по source ship/contract/dock функциями, исправить реально растущий C-owned путь, cached-vs-oracle, paid legs, tie-break; N39 caller согласовать с A |
| **D — markets+factions** | markets 39.43s, factions 39.34s за 300 ticks | Обнаружить рост списков, повторных full scans и event due на реальном D-owned пути, внести measured optimization и negative ordering oracle |
| **B — ledger/N38** | потенциальный рост receipts/journal/save bytes, не установлен | Измерить delta receipts, snapshot/scan cost, encoded N38; исправлять только подтверждённый B-owned hotpath; не создавать неиспользуемые индексы |
| **E — измерения/приёмка** | worker/UI уже реализованы, платные тики продолжают замедляться | Единые counters true CPU/paid tick vs elapsed worker request+DTO, size receipts/contracts/dock/events, bounded early/late benchmark, parity gates; не писать новый GUI |

**Договор результата:** не считать «производительностью» commit, new regression без runtime, or green 2-tick boot. На каждом checkpoint показывать phase cost (avg/p95 ms per *paid tick*), вызовы и время конкретного site, объёмы растущих данных, before/after same seed и exact N9/N39/N38/BT/RNG/cargo/contract parity. Аварийные диагностические CI ≤12 мин, никаких 420/900/2600 × несколько вариантов в одном job; не повторять 35-минутный отменённый run. Если runtime нет — писать безопасный код/targeted тест через GitHub connector, честно CODE_UNVERIFIED/TEST_ADDED_NOT_RUN.


> **Контроль E (обновлено 16.11):** opt-in worker **уже подключён к `main.gd`**, а не только прототип. По умолчанию оставлен прямой backend, эксперимент `LS_N158_WORKER_GUI=1` или `godot/run-worker-gui-windows.cmd`. GitHub Actions [#43842795997](https://github.com/Mefits/Living-Sector/actions/runs/43842795997) PASS: оригинальный F5, threaded F5+N38, direct/thread replay 9 тиков и 5 delta, live SceneTree 32 paid ticks/576 GUI frames/4.0s/UI p95 1.65 ms (Linux headless). **Windows FPS при тике ~601 пока НЕ измерен; по умолчанию НЕ включать.** Handoff: `godot/docs/performance/handoffs/20261116-perf-e-worker-main-f5-32ticks-verified.md`. Не дублировать этот блок; следующее — Windows F5 FPS/parity, затем opt-in 420/N38 restart.


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

## Обязательный рабочий протокол для автономных смен (обновление 16.11)

**Главная корректировка после реального запуска D без кода:** отсутствие локального `godot`, `git`, прямого DNS или возможности проверить все файлы в `leases/` НЕ ЯВЛЯЕТСЯ причиной остановить разработку. GitHub connector уже позволил смене E реально записать код в PR #262. Любое утверждение «не могу работать, потому что нет git/Godot» при доступных GitHub-инструментах противоречит цели задания.

1. **СРАЗУ работай через подключённый GitHub app, а не через `git clone`/shell.** В `functions.exec` найди по `ALL_TOOLS` точные инструменты `mcp__GitHub__get_pr_info`, `mcp__GitHub__fetch_file`, `mcp__GitHub__create_file`, `mcp__GitHub__update_file` и при необходимости `mcp__GitHub__fetch`. Пример: `await tools.mcp__GitHub__fetch_file({repository_full_name:"Mefits/Living-Sector",path:"godot/scripts/sim/event_queue.gd",ref:"integration/perf-astra-5-workers-20261116"})`. Для изменения: `update_file({repository_full_name, path, branch, content:<полный изменённый UTF-8 файл>, sha:<текущий blob SHA из fetch_file>, message:"perf(D): ..."})`. Для нового теста: `create_file({repository_full_name,path,branch,content,message})`. GitHub connector работает, даже когда shell DNS не работает. Никогда не писать по умолчанию в `main`.
2. **Прочитай текущий HEAD, план, изменённые файлы своего домена, затем начинай КОД.** Не расходуй весь запуск на чтение сотен handoff, аудит всего репозитория или обсуждение. Просмотр паритета и прошлых CI — контекст, не стоп-фактор для независимого модуля. Если текущий Godot CI медленный или отменён, продолжай несвязанные безопасные изменения и тесты; не объявляй их проверенными.
3. **Резервации не должны блокировать собственные файлы.** Первичным взаимным исключением служит жёсткое закрепление подсистем A/B/C/D/E. Для файлов своего направления проверяй последние изменения/признаки чужого одновременного редактирования, затем работай. Lease в `godot/docs/performance/leases/` делай, если можешь, но отсутствие папки, листинга leases или подтверждения всех чужих lease **не останавливает работу в своём домене**. Если нужен файл чужого владельца, НЕ правь его: вынеси самостоятельный адаптер/тест в своём домене и опиши конкретный интерфейс в handoff для владельца. Не создавать бесконечные резервации, не перезаписывать чужое.
4. **Нет Godot 4.7.2 → НЕ прекращать разработку.** Изменить реальный GDScript файл; добавить/доработать targeted тест с исполнимым смыслом; вручную проверить синтаксис важных участков, уникальность путей `res://`, существование preload через GitHub, единый стиль отступов, точное соответствие сигнатурам, отсутствие mutable alias. Пометь `CODE_UNVERIFIED`, `TEST_ADDED_NOT_RUN` отдельно. Не утверждай PASS и не подключай рискованный непроверенный backend по умолчанию: для опасных изменений используй opt-in flag или независимый модуль до CI.
5. **Каждый запуск обязан стремиться оставить работающий GitHub-след:** минимум один commit с существенным кодом и сопутствующим targeted тестом/negative regression; затем отдельный маленький handoff с SHA, пробелами проверки и конкретным следующим шагом. Если путь огромный и блок не помещается, закончи один автономный безопасный подблок со своим тестом, не ограничивайся планом. Честный отчёт без коммита допустим **только если отказывает сам GitHub connector на ЧТЕНИЕ или ЗАПИСЬ, либо есть подтверждённый конфликт безопасности со всеми возможными независимыми файлами**. В таком случае явно укажи точную ошибку и какой инструмент отказал.
6. **Соревнование пяти писателей:** перед каждой `update_file` взять свежий blob SHA; CAS-конфликт означает перечитать текущую версию и повторно применить ТОЛЬКО собственные изменения. Не `force-push`; не создавать отдельные рабочие PR. Новые уникальные тесты и handoff — непересекающиеся файлы. Не переносить весь PR #261, пока не проверены исходники и безопасный baseline. Нельзя менять чужой домен ради быстрого выигрыша.
7. **CI:** локального Godot может не быть. GitHub Actions #43762574707 по PR #261 подтвердил parser и 16-tick worker; 420-tick N39 был CANCELLED спустя ~34 минуты, worker420 SKIPPED. Это не ошибка паритета и не green light. Не запускать повторно длинный тест под тем же общим 35-минутным budget. После *крупного набора* кода — согласовать один ограниченный Actions checkpoint: parser + targeted tests и отдельно bounded профилировщик, без слепого 420×3. Сохранять реальные логи. Не изменять workflows/CI trigger в каждом запуске.
8. **Инварианты:** один authoritative World/N39, N9 ledger, N158 tick/clock, N38, source Rust 0.6.7 cadence; exact replay/BT/RNG/contracts/cargo/receipts; no fake ship movement, no bypass paid transaction, no AI budget reduction. Сравнение полного checkpoint, N38 restart и негативные tests — требования приёмки, но НЕ причина не писать отдельно тестируемые безопасные кодовые блоки до появления Godot.
9. **Короткий финальный отчёт каждой итерации:** `CODE COMMIT: SHA/нет`, `FILES`, `TEST EXECUTED: PASS/FAIL/NOT RUN`, `WHY`, `NEXT`. Если не было коммита, это не выполненная смена разработки независимо от количества прочитанных документов.

### Ближайший выбор реальных блоков при отсутствии Godot

- **A:** выбрать один готовый N39 write-set / локальный validator; добавить regression на старый Schema oracle; сохранить безопасный код без отключения полного guard.
- **B:** новый изолированный method/index + negative test на N9 immutable receipts, или real encoded-size metrics в N38, без migration включения vNext.
- **C:** независимый route/index invalidation patch + cached/uncached oracle test; не трогать N39.
- **D:** **не повторять только анализ `event_queue.gd`**; реализовать deterministic due-index/heap или безопасный индекс `(faction,location)` и тест с идентичным порядком событий. Если ускорение не доказано — оставить изолированный эксперимент с тестом и пометкой не включать до профиля.
- **E:** уже появился отдельный `n158_committed_frame_view.gd` с тестом; перейти к следующему реальному работающему модулю для очереди worker→FrameView→UI, не заявляя FPS до включения main и Windows проверки.

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

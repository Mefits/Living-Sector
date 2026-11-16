# Living Sector — 17.11.2026: защита двух готовых фиксов и независимый аудит памяти

Состояние на момент подготовки: PR #262, ветка `integration/perf-astra-5-workers-20261116`.
Проверенная отдельно рабочая база: `integration/godot-current-20261116` = `de1743a085a97175c0e39c1bb31277217cf36fd4`; **не менять** эту базу и `main` без отдельного решения.

## Уже внесено Астрой — НЕ дублировать

1. `99ab25e985c85fed2a80a1944a7fe911f9584828` — [GitHub](https://github.com/Mefits/Living-Sector/commit/99ab25e985c85fed2a80a1944a7fe911f9584828): N9 Ledger `_fork_source` теперь WeakRef (без удержания родителей); N152 `stage_owned` на no-change ticks без полной N9-history snapshot/restore; N91 получает только существующие funding-receipts; N39 engineer assign изменяет только ship rows. Есть `p2_late_growth_weak_parent_check.gd`; исходный fix был `[skip ci]`.
2. `1676db61af75effc99857e143f78463acbbc5ace` — [GitHub](https://github.com/Mefits/Living-Sector/commit/1676db61af75effc99857e143f78463acbbc5ace): 8 N158 полных `world_snapshot()` callsites заменены свежими N39 `native_runtime_read_snapshot(kind)` / `native_dock_read_snapshot`; статических мест было 27, стало 19. Для A/B `LS_RUNTIME_FULL_WORLD_READS=1`; есть `p2_runtime_read_projection_check.gd`. Исходный fix был `[skip ci]`.

**Принцип:** CODE_COMMITTED ≠ RUNTIME_VERIFIED ≠ PERFORMANCE_PROVEN. Не переписывать эти же точки до доказанного регресса. Следующие исполнители должны тестировать и исследовать НЕЗАКРЫТЫЕ пути.

## Текущее состояние 14 направлений исходного аудита, строгая методика

На tldraw странице «Оптимизация» сохранён первоначальный строгий подсчёт **3 полностью реализованы/принимались, 7 частично, 4 долгосрочных не начаты**. Старое «5/14» было более оптимистичным и засчитывало worker/UI без длительной Windows- и late-tick-приёмки; не смешивать оценки.
- Этап I (6): N21 one-snapshot, accounts-once, N84 ship write contract — внедрены; bounded reads, UI projection, полные metrics — частично.
- Этап II (4): N9 journal/transactions, N39 ownership/validators, индексы, worker scheduler — реализованы значимые части, но долгосрочные условия закрытия не подтверждены все.
- Этап III (4): packed data stores, native kernels, deterministic parallel compute, N38 segmented archive — не реализованы как законченные подсистемы.

Проверенный Linux HEAD **до двух новых фиксов**, CI 500 настоящих paid ticks + worker F5 + N38 + A–E regressions: https://github.com/Mefits/Living-Sector/actions/runs/43947575889 (de1743a). Отдельный исторический early/late A/B на c96920f: 2600 tick 1647→708ms, parity 32/32; нельзя переносить этот коэффициент на нынешний HEAD: https://github.com/Mefits/Living-Sector/actions/runs/43914178839.

## Независимый статический аудит — 17 ноября

**Найдено: диагностическое удержание памяти при LS_PROFILE_NATIVE_PHASES=1 (код подтверждён, runtime-эффект не измерен).**
- `godot/scripts/sim/phase1/n39_native_world_production.gd::_record_timing`: `samples_usec.append(elapsed)` без лимита для каждого `_profile_copy_sites/_profile_schema_sites`. `_cost_percentiles` дублирует и сортирует весь растущий массив; при долгом профилировании растут память и стоимость публикации. В обычном режиме `LS_PROFILE_NATIVE_PHASES` выключен.
- `godot/scripts/sim/phase2/n158_production_runtime.gd::_profile_ship_stage`: `_profile_ship_samples[key].append(...)` без лимита при включённом том же профилере; `profile_native_ship_subphases` копирует/сортирует всё. Следовательно 10k/100k profiling ticks не будут constant-memory. Исправлять через bounded window/histogram с чётким определением p95, без сохранения в World/N38; поручение E.

**Найдено: вероятный остаточный O(история контрактов) hotpath N152, несмотря на 99ab (исходник подтверждён, доля CPU не измерена).**
- `godot/scripts/sim/phase2/unified_n152_contract_lifecycle.gd::_stage`: на каждом вызове `ContractBoard.restore(original)`, `NativeAging.advance_posted(original["contracts"])`, `original.duplicate(true)`, повторный `ContractBoard.restore(aged_board)`, `board.snapshot()`, даже если `changed=false`.
- `godot/scripts/sim/native_contract_aging.gd::advance_posted` вызывает три последовательных deep-copy-прохода по `contracts` (`age_open_reputation`, `age_escalate_payment`, `sweep_expiring`).
- `godot/scripts/sim/economy/contract_board.gd::restore` валидирует и копирует все `_contracts` и receipt_claims. Это **не** значит, что можно удалить проверку — сначала измерить live count/time при старении и no-op; затем сравнить strict oracle, оригинальный порядок, refunds/escrow, N38.
- Это **не утечка памяти** в прямом смысле, а возможное сверхлинейное накопление CPU по мере роста contract history. D проверяет с A/B, не переписывает вслепую.

**Найдено: другие ещё дорогие полные снимки/commit (горячесть не доказана).**
- `N39.run_tick`: `_copy_world("L196", true)` каждый оплаченный facilities-tick.
- `N39` одно из publish-плеч: `_world = staged.duplicate(true)` после полной Schema/accounts проверки; нужно измерить callsite/частоту, прежде чем менять.
- `N158`: после 1676 осталось 19 статических `world_snapshot()` callsites. Не все выполняются за один тик; считать фактическую кратность через profiler.
- `N9`: полные `snapshot/restore` намеренно остаются на реальных платёжных границах, не объявлять их автоматически «утечками».

**Проверены также ложные кандидаты:**
- `event_queue.gd`: `_pending` имеет лимит 100000, `take_due` удаляет отработанные события, `_positions` и `_due_counts` синхронизируются; на просмотренных путях бесконечного хранения событий не видно.
- `N150` market trends: `while trends.size() > MARKET_TREND_KEEP: trends.pop_front()` — явно ограниченная история.
- `N153` transient `posture_cache/system_cache` создаются внутри одного propose call; не доказано долгоживущее удержание.

**Риски проверки нового 1676:** строки population/station-demand/dock — частичные проекции; короткий isolation fixture недостаточен для полной семантической совместимости. Требуется same-seed exact checkpoint A/B с `LS_RUNTIME_FULL_WORLD_READS=1` против default, включая N9/World/BT/RNG/cargo/contracts, и проверки отсутствующих/неполных строк.

## Краткая приёмка для следующих смен

В этом рабочем сеансе добавлены `godot/tests/p2_perf_pr262_astra_fixes_160_parity.gd` и ограниченный workflow `p2-pr262-head-500-acceptance.yml` (2 новых targeted теста, парный same-seed 160 real paid ticks, строгий checkpoint SHA, 500 paid ticks и worker/N38). CI job максимум 10 минут; не запускать старый 2600-tick replay на каждый коммит. Ссылка конкретного запуска: https://github.com/Mefits/Living-Sector/actions/runs/43972442164.

Независимый аудит — чтение исходников и статическая проверка. Реальная Windows late-tick скорость/утечка памяти требуют отдельного замера.

# N148 — оригинальный жизненный цикл корабля: банкротство, застой, списание, замена и wire snapshot

**Источник:** замороженная `archive/rust-galaxy-067-reference` в `Mefits/Living-Sector`. Атомарная резервация `godot/docs/nightshift/claims/N148.json` в общей `feature/godot-nightshift-20261112` создана первой: commit `fa7673ec`. Отдельная рабочая ветка `feature/godot-n148-native-ship-lifecycle-retirement-20261113`. Макро №3, Фаза 1 — **перенос исходников**, НЕ интеграция.

## Точное происхождение механики

- `native/crates/sim_core/src/agents/ship/components.rs` — `ShipLifecycle {broke_strikes:u8, hoard_strikes:u8, idle_ticks:u32, dirty:bool}`, постоянные `STRIKE_CHECK_INTERVAL_BASE=500`, `MAX_STRIKES=3`, `BROKE_CREDITS_THRESHOLD=500`, `BROKE_RECOVERY_THRESHOLD=5000`, `HOARD_CREDITS_THRESHOLD=200000`, `HOARD_IDLE_THRESHOLD=500`.
- `native/crates/sim_core/src/agents/ship/behavior.rs`, idle/strike branch near lines 1025–1070: на **активном**, прошедшем LOD корабле текущее `current_goal.starts_with("idle")` прибавляет ровно 1 idle tick; другой план сбрасывает idle в 0. Каждые **500×tick_multiplier** native ticks (если multiplier не ноль) при реальном cargo.used()==0, отсутствии `active_contract_id` и credits **строго меньше 500** начисляется один bankruptcy strike. После восстановления **до 5000 и выше** broke strikes сбрасываются в 0. Cargo/контракт не сбрасывают старые broke strikes. При credits **строго больше 200000** и idle_ticks **строго больше 500** один hoard strike добавляется на этом же cadence. Его обычное прекращение простоя **не** стирает; только confirmed delivery.
- При достижении **трёх** strikes формируется `SimCommand::DecommissionShip`. При обоих порогах банкротство имеет приоритет над стагнацией. `u8/u32` в Rust насыщаются. Разовый вызов GDScript не удаляет корабль и не создаёт замену.
- `native/crates/sim_server/src/engine/apply.rs` — `DecommissionShip` попадает в `AgentStore.pending_decommissions`, а успешная delivery apply отдельно сбрасывает `hoard_strikes=0` (не затрагивая `idle_ticks`/broke). Между повторными командами **в исходнике нет автоматической дедупликации в очередь**: после первого настоящего удаления engine drain пропускает устаревшие entity handles.
- `native/crates/sim_server/src/engine/drains.rs` — `drain_pending_decommissions` использует существующий `admin_remove_ship` (с настоящим DB delete, событиями, ledger cleanup), убеждается, что `ship_by_id` действительно исчез. **Если WorldTuning.auto_replace_retired_ships=true**, ставит `PendingRespawn {spawn_at_tick:tick+300+(tick%300), prefer_faction:retired_faction}`. **Если false (Genesis)**, выпускает `fleet_loss_unreplaced` и НИКОГДА не создаёт бесплатный корабль; новые корпуса только из оплаченной верфи (макро №6). `drain_pending_respawns` подавляет все старые заявки при переключении мира в конечные корабли, иначе допускает только заявки со `spawn_at_tick<=tick`. Само создание нового корпуса, выбор location/class и DB INSERT — server Phase2 authority, не исходная логика переопределения здесь.
- `native/crates/sim_core/src/agents/ship/snapshot.rs::ShipSnapshot::build` — отдельный **HTTP/WS read-only wire snapshot** из настоящих ECS-компонентов. Это НЕ `N54` checkpoint save; содержит id/faction/size/size_tier/location/docked/transit/cargo/credits/goal/BT/position, 3 lifecycle counters, округлённые исключительно для UI crew morale/fatigue/hunger/health, crew wages_credits, optional skills/fitting/progression/reputation. Morale + fatigue + hunger принадлежат **оригинальной Elixir CrewComplement**, не новая придуманная нами концепция; N138 переносит фактическую симуляцию этих показателей.

## Какие файлы добавлены в N148

1. `godot/scripts/sim/phase1/n148_native_ship_lifecycle.gd`: source-exact pure `lifecycle_step`, saturating counters, actual N80 current_goal, N140 LOD-only fire, cadence, bankruptcy-first command; `after_confirmed_delivery` — clear hoard only with trusted internal actual delivery receipt. Не тратит пищу и зарплату (N72/N138) и не выбирает AI цели (N80).
2. `godot/scripts/sim/phase1/n148_native_ship_retirement_queue.gd`: source-exact stage/drain of N146 DecommissionShip intent into genuine AgentStore queue, deferred actual `admin_remove_ship` and success-only replacement policy `auto_replace_retired_ships`, pending respawn due/suppression; **no SQL, no world edit, no free hull in Genesis**.
3. `godot/scripts/sim/phase1/n148_native_ship_wire_snapshot.gd`: read-only original `ShipSnapshot` wire serialization, keys and omission rules (e.g., optional active_contract_id and empty faction_reputation omitted). N50 real initial crew, N51 fitting, N101 progression and N128 crew skills can be supplied without second renderer inventory. **Never restore world from this HTTP/WS view**.
4. `godot/scripts/sim/phase1/n148_native_ship_lifecycle_checks.gd`: **подготовлены, НЕ ЗАПУСКАЛИСЬ** source-derived examples: 500×mult cadence, u8/u32 saturation, below/at strict thresholds, LOD, committed cargo and contract protections, delivery reset, bankruptcy priority, no duplicate money/fuel/crew, queue after real removal, deterministic replacement delay, Genesis finite hulls, HTTP snapshot defaults/rounding/omission.

## Интеграция (ТОЛЬКО Фаза 2)

- На конце реального `behavior.rs::decide_and_act` для каждого ACTUALLY ACTIVE ship N80 phase (после выбора current_goal, перед одним BT step) вызвать `Life.lifecycle_step(`**real ShipLifecycle, ShipEconomy, ShipCargo.used(), identity entity**, tick, mult, true`). Только N146 authoritative ordered CommandBuffer принимает `commands` и только canonical tick runner обновляет dirty `ShipLifecycle`. При LOD skip не вызывать эффектов.
- При подтверждённом native `DeliverContract` apply, после реальных денег/груза/contract receipt, `after_confirmed_delivery` может сбросить только hoard-strikes. UI **никогда не имеет права** присылать такой receipt; `trusted_internal_apply=true` должен устанавливаться внутри exclusive engine, а не клиентом.
- N146 CommandBuffer → server Apply → `AgentStore.pending_decommissions` → текущий `admin_remove_ship` (household/DB/ledger/contract cleanup) → только после отсутствия ship_by_id подтверждать N148 `on_authoritative_ship_removed`. Если уже удалён предыдущей командой, очередная запись stale and skipped. При `WorldTuning.auto_replace_retired_ships=false` запрещён даровой respawn; N148 не добавляет новую shipyard craft функцию.
- Если Legacy `auto_replace_retired_ships=true`, очередь `PendingRespawn` должна быть обработана самим сервером через оригинальный `spawn_replacement_ship`, не посредством статических `SHIP_CLASSES` N148. Никакого second wallet/crew source нет; N50 crew и N52 credits требуют реального authoritative creation only.
- HTTP/WS `ShipSnapshot` — read-only из самой ECS, рисует экипаж и lifecycle после их истинного тика; N67 inspector, N54 authoritative save и N138 live crew economics остаются отдельными независимыми источниками.

## Исходная карта смежных переносов / оставшийся макро №3

| Группа оригинала | Чей уже порт / новый порт | Статус |
|---|---|---|
| ShipCrew initialization, roles, aggregate morale/hunger/fatigue/health | N50 #139 | source-only |
| Реальная пища и payroll, потребление по cadence | N72 #164 | source-only |
| Morale / health efficiency / shore leave and auto tasks | N138 #228 | source-only |
| Crew skill grants and ship XP/retrofit levels | N101 #190 и N128 #217 | source-only |
| Ship fitting module defaults and physics | N51 #141 | source-only |
| ShipLifecycle idle, strikes, confirmed delivery reset | **N148** | source-only |
| DecommissionShip command staging and finite/legacy delayed replacement | N146 #235 + **N148** | source-only |
| ShipSnapshot source HTTP/WS projection | **N148**, N67 #156 inspector projections | source-only |
| True ship-owned cash and source credits | N52 #142 | source-only |
| Actual navigation, docking, ship AI goals and their external actions | N59–N61, N80 and others — **макро №4**, not covered twice | source-only |
| Physical DB save and restore ships | N54 #144 and **макро №10** | source-only |

**Честный статус:** этот source slice **закрыт в рамках Фазы 1**, но **весь макроблок №3 пока не назван полностью закрытым**, до окончательной инвентаризации оставшихся `ShipCrew` branch paths, `ship/components.rs` и source-versus-PR parity. И все Nx остаются в независимых черновых PR. `CODE_UNVERIFIED`: нет Godot parser/headless/runtime, нет объединения в общий мир, нет полного Rust-vs-GDScript replay. Проведены только GitHub readback, статическая балансировка строк/скобок и проверка относительных preload.

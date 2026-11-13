# N157 — макроблок №10: физическое сохранение экономического кадра, восстановление и итоговый Rust source inventory

**Статус: SOURCE-MAPPED / CODE_UNVERIFIED (Фаза 1).** Эта работа **не** включает объединение десятков Draft PR и проверку живого Godot — это Фаза 2.

Резервация `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N157.json` сделана **до кода** (commit `2bd092c1`). Ветка `feature/godot-n157-macro10-source-persistence-20261113` основана на `integration/godot-47-n33-n37-20261112`. Источник: immutable `archive/rust-galaxy-067-reference@6e40615be95cc6ddbabe21c3b94def5c52f8622d`.

## Фактический source-to-GDScript перенос N157

| Rust 0.6.7 | Новый source-only компонент Godot | Сохраняемая семантика |
|---|---|---|
| `native/crates/sim_db/src/persistence.rs::DbWrite`, `key()` | `n157_native_db_write_contract.gd` | 19 категорий записей с ключом + EconomicFrame как двадцатая оболочка (не самостоятельный key); отдельные ключи facility create/site upsert/delete, ship delete; trend по (market,tick), retirement по (agent,tick); недопустимы случайные ECS Entity handles и анонимные операции |
| `PersistenceWorker::buffer_write/flush_buffer/run` + `engine/persist.rs::emit_persist_writes` | `n157_native_economic_frame_buffer.gd` | Сначала `try_reserve` всего экономического кадра, иначе **не** сбрасывать dirty; контрактная доска и tick являются обязательными полями того же кадра; dedup по категории/устойчивому ID; если следующий кадр не содержит неизменённый баланс, старый дебет остаётся в буфере; backpressure/retry; ack export только после успешного flush |
| `PersistenceWorker::flush` SQL transaction | `n157_native_persist_transaction.gd` | Immutable staged transaction с одним commit, порядок `facility_create(0) → colony(1) → обычные (2) → tombstone(3)`. `site_delete` и `ship_delete` побеждают stale upsert; full-board contracts удаляются и заменяются *атомарно* с balances/tick. Market trend INSERT OR REPLACE по (market,tick,commodity); retirement append separately |
| `sim_db/spawner.rs::load_agents`, `load_contracts`, `load_market_trend_samples`, `load_construction_sites` | `n157_native_boot_recovery.gd` | Порядок body→faction→facility→market→trends→population→ship→contracts→construction→gate pairs→price knowledge. Восстановление связи docked ship по постоянному DB-ID, а не ненадёжному ECS Entity, реальный `ShipResumeState`, cargo_age/origin/rejection. История рынков pivot+хранить последние 200, пропуск неизвестного контрактного enum/commodity и orphan trends; сохранённый funding; завершённая стройка не возрождается |
| `sim_core/spatial/grid.rs::UniformGrid<T>` | `n157_native_uniform_grid.gd` | Найденный при аудите **действительный** исходный механизм: spatial buckets по `floor(x/cell_size)`, вставка/перенос/удаление, точный поиск в радиусе по дистанции², ближайший, rebuild. Не дублирует N140 LOD или N59 pathfinder |
| Rust `#[test]` из persistence.rs, workforce, spatial/grid.rs | `n157_source_persistence_checks.gd`, `n157_source_grid_checks.gd`, `n157_headless_entry.gd` | Source-oriented deterministic fixtures; **написаны, НЕ запускались** |

**N157 не создаёт второй SQLite, второй Ledger или новый физический мир.** Его `n157_native_persist_transaction.gd` — чистый in-memory staged projection того, что Rust атомарно делает в SQLite. Реальное файловое сохранение `FileAccess`, backup/rename и проверка целостности **остаются в N32/N38** (например [PR #127](https://github.com/Mefits/Living-Sector/pull/127)). Phase2 должен подключить подтверждённый экономический кадр к **одному** авторитетному `SaveState` со всем реальным ECS, а не параллельному autosave.

## Проверенный исчерпывающий список исходных путей

Дополнение `N157_FROZEN_SOURCE_TRIAGE.json` автоматически составлено **из всех 793 записей** существующего `godot/docs/SOURCE_INVENTORY.json` без замены оригинала. Для **каждого из 159** canonical `native/crates/**.rs` записаны `path`, `git_blob`, конкретный класс источника, владелец и граница. Классы различают engine components, UI/transport replacements, активные source stubs и схему.

**Важное обнаружение:** из 224 файлов исторического корневого `crates/` у 133 есть `native/`-путь-пара, но только **92** имеют идентичный blob. **41** пара различается, поэтому нельзя делать ложный вывод «старый корень = эталон». **Активный источник — `native/`** замороженного SHA. Ещё 36 путей без старой классификации находятся в основном в meta/build/manuals; они не были молча объявлены игровыми механиками.

По существующим функциональным owner (НЕ новым дублям):
- N59 [PR #147](https://github.com/Mefits/Living-Sector/pull/147): оригинальный gate-aware Dijkstra pathfinder. N142 [PR #231](https://github.com/Mefits/Living-Sector/pull/231): source physical-only registry/travel. Не смешивать gate jumps с физической кратчайшей дистанцией.
- N140 [PR #230](https://github.com/Mefits/Living-Sector/pull/230): LOD и WorldTuning. N146 [PR #235](https://github.com/Mefits/Living-Sector/pull/235): native SimCommand buffer. N47: сохранение seed identity.
- N24, N32, N38: read-only diagnostics и FileAccess backup/integrity. N152 ContractBoard, N104 real escrow, N39 real paid production, N100/N155 plan, N148 ships, N150 markets, N154 physical facilities — их семантика сохраняется внутри единого экономического кадра, не порождает ещё один набор кошельков или контрактов.
- `sim_core/spatial/chunk_manager.rs`, `position_tracker.rs`, `quadtree.rs`, `simulation/tick.rs`, `world/body.rs` в frozen archive — **комментарий-заглушка без выполняемого кода**. Не придумывать реализацию из названий.
- 36 Bevy client Rust files — старое UI/render и звук, **в Godot создаётся другой клиент во Фазе 2**; `sim_protocol` и Axum/WS — старый транспорт, переносить API shape отдельно. Не выдавать отсутствие Bevy GUI копии за отсутствие Rust экономических механик.
- `native/crates/sim_db/pool.rs` SQLite WAL/migration scheduler: технический механизм storage заменяется Game SaveState (Godot FileAccess); `spawner/seeder` необходим в части порядка source entities и сохранения IDs, но полноценное подключение UI/ECS остаётся Phase2.

## Source closure gate (что конкретно значит 10/10)

После N157 **все десять макронаправлений распределены на существующие source-backed компоненты/сохранённые stubs/platform replacements**. Это метка **SOURCE-COVERED / CODE_UNVERIFIED**, НЕ «проверено в Godot» и НЕ «функционально работает вся игра». Соответствие 793 файлов *по предназначению* не равно побитовому совпадению поведения и не означает, что каждое изменённое Rust поле можно восстановить без Phase2 single World/Store integration.

Остаток Фазы 1 как **перечня неперенесённых активных source-областей** после N157 → **0 известных из десяти**; неизвестные ошибки source audit возможны. Следующая **Фаза 2** — интеграция PR, единый authoritative World/Market/ContractBoard/N9 Ledger/WorkShift/AgentLod, сборка/парсер Godot 4, сохранение ECS целиком в `N38 SaveState`, перезапуск, дифференциальные тесты на frozen Rust и устойчивый replay. **Фаза 3** — дополнительные исправления от Grok и новая механика.

## Минимальный запуск сценариев после объединения с Godot

`godot --headless --path godot --script res://scripts/sim/phase1/n157_headless_entry.gd`

На момент N157 ни Godot 4 парсер, ни сами проверки, ни single-engine ECS, ни Rust Rust-vs-Godot parity не запускались. Файлы только прочитаны обратно из GitHub и проверены статически.

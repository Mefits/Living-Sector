# Living Sector — Phase 2 / N158: первый работающий производственный срез

**Статус: INTEGRATION_CODE_UNVERIFIED.** Это **первая реальная сборка нескольких source-компонентов**, а не готовая игра и не полная интеграция всех PR. Сначала портированный source-only N39 [PR #246](https://github.com/Mefits/Living-Sector/pull/246) взят в единую ветку Godot (без merge main) и включён в существующие UI/время/сохранение.

- Рабочая ветка: `feature/godot-phase2-n158-production-boot-20261113`
- База: `integration/godot-47-n33-n37-20261112@1e4a1e9`
- Резервация: `godot/docs/nightshift/claims/N158.json`
- Замороженный эталон: `archive/rust-galaxy-067-reference@6e40615`
- GUI: `godot/scripts/main.gd` теперь создаёт `n158_production_runtime.gd` (не N23 demo).
- Сохранение из GUI: `user://saves/galaxy-067-p2-integration.json` (старый P1-сейв не перезаписывается).

## Что уже соединено

1. **Настоящий Seed**: `NativeData.load_current_world()` читает 8 систем, 3 фракции из `native/priv/galaxy/data/worlds/*.json`; `n158_galaxy_production_seed.gd` выбирает реальные source location и ровно одну станцию-владельца каждого рынка, не создаёт фантомных магазинов или населения. В текущем frozen seed это **15 предприятий, 3 рынка и 3 группы жителей** для производственного контура; прочие тела остаются в первичной модели орбит.
2. **Один источник финансового состояния в этом срезе**: N39 `n39_native_world_production.gd` с единственным собственным N9 ledger (внутри N39 actor), real facilities/populations, receipt-verified wages и owner-processing-fee, 14 real recipes по Rust, finite salvage и обычная добыча. Нет одновременного N23/параллельного ledger.
3. **Один TickRunner**: `n158_production_runtime.gd` наследует N39 native TickRunner → P1 orbit/events/clock/calendar. `bodies` выполняются до `facilities`. `tick_multiplier` вычисляется по настоящему Rust `TickConfig::tick_multiplier() = round(tps/world_speed)` **динамически**: при старте ×0.25 и 8 TPS multiplier=32, производство раз в **160 тиков**. При speed ×8 multiplier=1, выпуск раз в 5 тиков. Скорость не превращается в дополнительную зарплату вне нативной смены.
4. **UI из фактического состояния**: экран выбранной системы показывает текущие цены/запасы market (источник owner), wallets предприятий и последнее подтверждение смены. P1 seed/орбиты остаются immutable read-only геометрией; товарные остатки читаются **только** из N39 runtime snapshot. Footer указывает неподключённые фазы.
5. **Сохранение/рестарт**: P1 `SaveState` уже использует atomic FileAccess pending/bak. У N39 есть `native_production` в snapshot: рынок, зарплаты, worker receipts/last recipe output, crew XP, finite salvage, N9 ledgers. N158 restore нормализует только интегральные поля, которые стандартный Godot JSON мог разобрать как float, потом вызывает N39 существующий строгий preflight. Старый P1-save из отдельного пути и не загружается как полноценный экономический P2-save.

## Что не подключено — важно не врать пользователю

- **N151 population tick (потребление Food/Water)** НЕ работает здесь. Потребитель должен платить из **того же N9 ledger**, отдавать реальную запись MarketFlow, а не создать независимые кошельки.
- **N150 market pricing / demand / shortage**, N156 condition/repair/restock/missions, N152/N104 contract board/funded shipments, корабли и N100/N155 стратегический ИИ НЕ запускаются в N158; это следующая работа Фазы 2 с чёткой source ownership.
- N157 persistence frame/SQLite source projection ещё не слит в runtime; P2 N158 использует P1 FileAccess со snapshot N39 для первого вертикального среза. До поддержки всех ECS объектов не считать сейв полным сейвом игры.
- Внутренний N39 ledger *на этом этапе* единственный для производственных счетов, но Phase2 должен объединить его с остальными owner-ledgers N104/N152/N151/N154. До этого нельзя запускать дополнительные source snapshots на одинаковых балансах.
- Демо N23 нельзя запускать в общей игре одновременно с N39, а N39 stage world не может считаться полной моделью всей Galaxy. В текущем source seed все 15 существующих предприятий находятся у 3 рыночных локаций; future construction/sites может добавить другие.

## Проверка на компьютере с Godot 4

Запустить:

`godot --headless --path godot --script res://tests/p2_n158_live_production_check.gd`

или Windows `godot/RUN-P2-N158-CHECK.cmd` (использует `GODOT_EXE` если Godot не в PATH).

Тест создаёт реальный frozen seed, проверяет pause/no-free-output, динамический ×8 tick multiplier, именно paid N39 производственный выпуск после 5 тиков, сумму реальных денег, настоящий файл и восстановление, отказ отрицательных запасов и продолжение после рестарта до тика 10.

**На момент подготовки PR: GitHub readback+скобки/строки+preload пути проверены. Godot binary в доступном контейнере отсутствует, реальный parser/headless НЕ запускался, поэтому `INTEGRATION_CODE_UNVERIFIED`; ни один VERIFIED-метрический счётчик не увеличен.**

## Последующие крупные блоки Фазы 2

| Этап | Содержание и единые владельцы |
|---|---|
| **P2-02** | Привязать N151 paid population consumption + N150 market recalculation к *одному* N9 ledger и реальному MarketFlow; N156 upkeep и N141 construction paid labor к общему occupied_workers, не копировать cash |
| **P2-03** | N152 ContractBoard/N104 escrow + N97 actual ship Apply/physical trade, N153 ship AI/BT + N149 crew, N140 LOD + N59/N142 directed travel в одном мире/порядке |
| **P2-04** | N100/N155 HTN/GOAP/Beam + N134 Head, N143 research, N154 construction/shipyard. Принятие решений влияет только через подтверждённые receipts |
| **P2-05** | N157 full economic-frame + single save/restore ECS/market trends/director/ships/contracts, N38 integrity fallback, Rust vs Godot parity seeds and actual executable Windows portable build |

План — ориентир владения задачами и порядок технических зависимостей, не гарантия что интеграция пройдёт без дополнительных дефектов.

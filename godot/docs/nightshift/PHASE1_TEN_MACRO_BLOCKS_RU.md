# Living Sector — десять крупных направлений остатка Фазы 1 (12.11.2026)

План согласован с пользовательской командой: ускорять **полный перенос реального функционала замороженной Rust Galaxy 0.6.7 в GDScript**, не разбивая одну исходную подсистему искусственно на десятки мелких PR. После полного покрытия Rust → **Фаза 2**: единый работающий Godot 4, интеграция и проверка; после неё **Фаза 3**: дополнительные исправления Grok.

**Исходный снимок оценки:** 58–61% всего труда Фазы 1 ещё осталось после [N135 / PR #225](https://github.com/Mefits/Living-Sector/pull/225). Ниже доли **внутри этого оставшегося объёма**, не абсолютные проценты всей игры. Это экспертная маршрутизация, не измерение строк и не гарантия полного покрытия за 10 PR. Не путать `CODE_UNVERIFIED` с работающим Godot. При открытии новых PR сверять claims и текущие ветки; уже начатые чужие Nx не перехватывать.

| Макро | Остаток | Объём исходного Rust / критерий закрытия Фазы 1 | Существующее покрытие / границы |
|---|---:|---|---|
| **1. Экономика / производственный такт** | **14%** | `economy/recipes.rs`, `agents/facility/*`, `facility_modules/*`: физический input→output, рабочие смены, денежные перемещения, остатки, upkeep, без фиктивных товаров; все native варианты рецептов и блокировок | N6/N8/N23/N39/N116/N130/N132; **N39 занят другим исполнителем**, не трогать |
| **2. Население / колонии** | **10%** | `agents/population.rs`, `strategy/colony.rs`, `strategy/colony_development.rs`, миграция, хозяйства, потребление, создание физической колонии и кризисы без телепортации | N71/N92/N114/N118/N123/N125–N127 покрывают фрагменты; не считать всю подсистему интегрированной |
| **3. Корабельная жизнь** | **10%** | `agents/ship/mod.rs` и `ship/components.rs`: жизненный цикл, питание, здоровье/мораль, усталость, задачи пилота/торговца, отдых, заработок, производительность, LOD и сохранение | N50 и N72 покрывают init/часть upkeep, N101/N128 XP; **N138 переносит недостающие morale/task/efficiency** без второго расхода еды/зарплаты |
| **4. Автономный корабельный ИИ** | **14%** | `agents/ship/behavior.rs` (~145 KB), `agents/ship/actions.rs`, `ai/*`: полный выбор целей, BT, планирование/перепланирование, trade/explore/mining/contract/refit, безопасный rest/dock | N80/N83/N84–N88/N90/N103/N112/N137 покрывают некоторые функции; необходим аудит остальных ветвей |
| **5. Контракты / физическая логистика** | **10%** | `economy/contracts.rs`, `strategy/orders.rs`, `sim_server/engine/transactions.rs`: полный набор delivery/passenger/build, escrow, приёмка, одноразовый физический receipt, ошибки, отмены | N15/N16/N25–N31/N90/N97/N104/N108/**N135**; второй раз не портировать готовый dispatcher |
| **6. Стройки / верфи / инфраструктура** | **11%** | `agents/construction/*`, `strategy/construction.rs`, `economy/module_production.rs`, sim_server shipyard: ресурсы, оплаченный труд, производство кораблей, site lifecycle, upgrade; не за один фиктивный шаг | N17/N75/N77/N79/N91/N110/N119/N132 — фрагменты, проверять полную source-parity |
| **7. Глава фракции / администраторы / планировщики** | **11%** | `strategy/director.rs`, `strategy/coordination.rs`, `strategy/planning/*`, `strategy/long_term.rs`: durable цели, реальный бюджет, GOAP/HTN/Beam/Hybrid, иерархия решений, без дублирования grant | N19/N81/N93/N98–N100/N106/N107/N113/N117/N121/**N134**. N100 частично в работе; не перехватывать |
| **8. Наука / прогресс развития — SOURCE-COVERED (N143)** | **6% первоначального остатка, теперь покрыто исходниками** | `strategy/progression.rs`, research в `strategy/director.rs`/`governance.rs`/sim_server: исходные 12 tech, реальные оплаченые смены, мандаты, прогресс, послеоплатные unlock — **source-domain завершён, runtime NOT VERIFIED** | N44/N45/N76/N82/N89/N110/N120/**N143 PR #233**; уже перенесено несколькими **неслитыми PR**, НЕ брать повторно, стыковка и тесты — Фаза 2, physical station upgrades — макро #6 |
| **9. Рынки / дипломатия / территория** | **7%** | `agents/market.rs`, `agents/faction_relations.rs`, `economy/price_engine.rs`, body territory: реальные товары/цены/торговые договоры/санкции/динамика рынка, без второй книги денег | N68/N69/N94/N115/N122/N124/N129/N131/N136; искать ещё не покрытые source branches |
| **10. Сохранения / скрытые механики / полная исходная карта** | **7%** | `sim_core/src/world/*`, `sim_server/src/*`, `simulation/*`, `SOURCE_INVENTORY.json`: незамеченные исходные правила, serialize/deserialize states, deterministic ordering, source inventories и replay contracts | N4/N24/N32/N38/N46 и др.; **не форсировать общую сборку Фазы 2** в этом пункте |

**Итого: 100% приблизительного остатка Фазы 1.** «Крупный блок» — направление, не автоматический claim. Для каждой реально выполняемой итерации нужен **один** новый уникальный Nx в `claims/` до кода и отдельная ветка/PR; другой чат может брать иное независимое направление. Не создавать заранее 10 claims. Перевод в `CODE_UNVERIFIED` означает исходники готовы, но не тестировались в живом Godot.

## Распределение пяти автоматических смен (12.11.2026)

Установлено непосредственно в промпты **всех пяти** существующих включённых запланированных задач. Расписания не изменены. Это приоритеты, **не эксклюзивная монополия на целое направление**: разные рабочие чаты вправе одновременно переносить отдельные незанятые Rust source scopes внутри одного макроблока.

| Задача | Приоритетное направление | Резервное направление |
|---|---|---|
| `Living Sector — ночной перенос 1` | **№6** Строительство, верфи, инфраструктура | **№1** Экономика, производство |
| `Living Sector — вторая ночная смена` | **№2** Население и колонии | **№8** Наука и исследования |
| `Living Sector — третья смена` | **№4** Корабельный ИИ | **№3** Корабельная жизнь |
| `Living Sector — ночная смена 03:30` | **№5** Контракты и логистика | **№9** Рынки, дипломатия, территория |
| `Living Sector — ночная смена 03:35` | **№7** ИИ фракций, администраторы, планировщики | **№10** Сохранения и остальные исходные механики |

**Порядок каждой смены:** сначала прочитать именно актуальную версию этого плана, очередь, журнал, трекер, claims и PR. Завершить свой собственный `IN_PROGRESS` прежде нового бронирования. Выбрать реально свободную существенную Rust-подсистему основного макро, атомарно создать **только один** новый `claims/Nx.json` на точный исходный scope (добавить `macro_id`), отметить `IN_PROGRESS` и сделать реальный большой GDScript перенос в своей ветке с PR/handoff. При отсутствии доступного scope перейти на резервное направление; при отсутствии обоих — на любое другое из десяти со свободной работой и объяснить выбор. Не заниматься интеграцией Фазы 2 или фиксом Grok до полного source coverage. Не трогать N39/N100 и любые чужие claims, не дублировать уже опубликованные куски. После работы обновить claim, очередь, журнал, трекер и покрытие макро, указать остаток макро и символический общий остаток Фазы 1. Статус `CODE_UNVERIFIED` до реальных проверок в Godot, не выдавать за VERIFIED.

## Выбранное направление

**№3, N138, `interactive-chat`**: проверка frozen `ShipCrew` выявила, что существующий N72 уже считает часть голода, еды, зарплат и шкалу усталости, но упрощает мораль, переключение ролей и финальный efficiency. N138 **не** повторяет расход пищи/денег, а переносит истинные Rust welfare/occupation phases и гарантирует, что во второй фазе они будут вставлены между физическими стадиями N72 строго в исходном порядке. **Важно:** ветки N72 и N138 не следует запускать независимо в одном тике; сначала нужен один авторитетный Phase-2 adapter. Один из нюансов: Rust выбирает Eating по голоду *до* физического приёма пищи, даже если после съедания еды уровень голода упал ниже порога.

## Обновление оценки

Каждый новый завершённый компонент может уточнить остаток; изменение процентов не связано линейно с количеством Nx. Главный критерий завершения Фазы 1 — фактическое исходное покрытие всех механик Rust, с честным перечнем не перенесённых фрагментов, а не 10 отчётов или 10 PR.

### Макро №6 — N141: точная оплата строительных смен (12.11.2026)
- [PR #229](https://github.com/Mefits/Living-Sector/pull/229), `CODE_UNVERIFIED`: перенесены `agents/construction/labor.rs::work/commit`, общая резервация работников `facility/workforce.rs::occupied_workers` и пересчёт занятости. 10 работников/тик, 60% доступных жителей, реальные зарплаты 1 CR, общий ресурс рабочих с производством, сортировка household ID, оплаченная квитанция, защита от повторной смены. N77/N91/N39 не переписаны; исходный executor::present остаётся внешней обязательной проверкой.
- **Остаток макро №6:** полный серверный site materialization в предприятие, цикл заказ→производство→спуск корабля на верфи, upgrade инфраструктуры и исходные ветви strategy/construction.rs. N39 чужой claim. Это не закрывает макро целиком. Общий символический остаток Фазы 1 пока **~58–61%** (без механического уменьшения за один PR). Сборка/тесты — Фаза 2.

## 12.11.2026 — макро №10, реализация N140
- **[N140 / Draft PR #230](https://github.com/Mefits/Living-Sector/pull/230)** переносит именно ранее свободные frozen Rust `simulation/lod.rs` (279 строк) и `simulation/tuning.rs` (204 строки) как standalone GDScript. Код без Godot runtime, `CODE_UNVERIFIED`.
- Готовая часть №10: persistent per-agent LOD cursor, ship-only gate, nearest observer/6-tier spatial distance, recompute stats; все 12 WorldTuning defaults/once-install/partial JSON и finite Genesis switches. Не повторять в других сменах. Авторитетный интеграционный consumer — Фаза 2.
- **Осталось в макро №10:** исходный `world/registry.rs` / `world/pathfinder.rs` / `world/travel.rs` gap-versus-N58–N61 audit, spawner/seed source parity, remaining `simulation/*` configuration/commands, snapshots and deterministic recovery coverage. Другие направления не считать закрытыми.
- **Общий символический остаток Фазы 1:** ~57–60% вместо прежних 58–61%, не по числу PR. Доли десяти направлений остаются первоначальными ориентировочными, суммарно 100% на момент составления; после каждого source port их нужно переоценивать по покрытию, а не «вычитать» целый блок по одному PR.

## 12.11.2026 — макро №10: N142 реестр мира и физические расстояния
- **[N142 / PR #231](https://github.com/Mefits/Living-Sector/pull/231)**: исходный `world/registry.rs` (127 строк) и `world/travel.rs` (67 строк) с `simulation/config.rs::TickConfig` перенесены самостоятельными GDScript моделями — directed physical-only shortest_distance, first-edge travel_distance, actual location/system metadata, legacy travel_ticks/arrival/progress. 4 файла, 559 новых строк, `CODE_UNVERIFIED` (Godot не запускался).
- **Проверка на дубли:** N58 граф из замороженного seed, N59 gate-aware Dijkstra (`pathfinder.rs`, вес ворот 5), N60/N61 условия и выполнение одного реального перелёта, N108 платный GateJump Apply, N112 динамическое преследование движущихся тел — уже в отдельных PR; НИЧЕГО из них N142 не переписывает. Различие существенно для бюджета администрации: `WorldRegistry.shortest_distance` НЕ учитывает врата. Стыковка без повторной проводки — Фаза 2.
- **Остаток макро №10 после N140 и N142:** DB spawner / seed нормализация, недостающие Rust `simulation/commands.rs`, server world state, authoritative save/replay/persistence, другие не перенесённые функции из полного source inventory. Общее оставшееся покрытие Фазы 1 оцениваем **около 57–60%** — не считать по количеству PR и не объявлять весь макроблок закрытым.

### Макро №2 — N144, 12.11.2026
- [PR #232](https://github.com/Mefits/Living-Sector/pull/232), CODE_UNVERIFIED: Rust colony proposal selection/ranking and active-site continuation with physical routes, resource-bearing planets, technology, settler, transport and funded metals quote checks. Separate from N79 admission/N118 paid commission/N92 aftercare.
- **Остаток макро №2:** full source parity for population migration and colony aftercare paid passenger commitment, authoritative population transfer and crisis application, Phase 2 unified execution. Symbolic overall remaining Phase 1 ~57–60% (not Nx count); no runtime acceptance.

## 12.11.2026 — макроблок №8: исходное покрытие науки ЗАКРЫТО (N143)

**Результат:** [Draft PR #233](https://github.com/Mefits/Living-Sector/pull/233), N143 `CODE_UNVERIFIED`, 4 файла / 725 LOC. Оригинал `strategy/director.rs` — `TECHNOLOGIES` (12 реальных технологий), `observe` выбор направления, `research_ready` проверки, `research` оплачиваемая наука; `strategy/governance.rs` — долгосрочное поручение и бюджет, `strategy/charter.rs` — разрешение/учёт реальной player-attributed оплаты. **Исходная научная механика покрыта всеми самостоятельными N44/N45/N76/N82/N89/N110/N120/N143 вместе**, с явной матрицей исходников в `N143_MACRO8_COMPLETE_RESEARCH_SOURCE_RU.md`.

**Закрыто именно для Фазы 1 — source domain port:** выбор/цель без сброса оплаченного прогресса; prereqs и 12 tech; Hold/Advise/Delegated и charter research autonomous/review; только реальный местный Electronics+staff; 10 работников, 1 electronics, оплата `ceil(price)+10` с реальными кошельками; 10 работы/смену, unlock лишь после подтверждённой транзакции; сохранение учёта мандата/charter. Источник `research_ready` требует строго `treasury > ceil(price)+10010`; реальный `research()` допускает `>=`, исходная граница сохранена.

**Не закрыто в качестве исполняемой игры:** нет Godot runtime test, GitHub PR НЕ слиты; N82/N45/N89/N120 и N143 будут объединяться в один реальный World+ledger+director save authority только в **Фазе 2**. Освоение T2/T3 через оплачиваемые материалы и строительные смены относится к макро **№6**; полноценные фракционные чартеры и стратегические портфели относятся к **№7**. 1000-летняя новая T4-наука — **Фаза 3**, не подмена frozen Rust.

**Учёт макроблоков после N143:** №8 — один полностью **source-covered** из десяти, **не VERIFIED** и не интегрирован. Остальные **9** направлений всё ещё имеют исходные непокрытые функции/нуждаются в source audit. Символическое оставшееся исходное покрытие всей Фазы 1 около **55–59%** (не статистика Godot-запусков, не число PR; грубая экспертная оценка).

### 13.11.2026 — макро №5: N145 Posted contract aging and renewal
- [Draft PR #234](https://github.com/Mefits/Living-Sector/pull/234), CODE_UNVERIFIED: frozen contracts.rs age_open_reputation, age_escalate_payment, sweep_expiring and posted_for_ship with tiered indexes; 12 standalone GDScript methods, source handoff, no escrow/physical stock effects.
- **Остаток макро №5:** сверить непокрытые Rust board queries/cleanup/contract-type nuances, затем Phase-2 atomic integration with N16/N104/N135/N97. Do not duplicate escrow/dispatch. Overall Phase-1 remaining remains symbolically ~55–59%; not a count of Nx or runtime proof.

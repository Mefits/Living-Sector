# N154 — Макроблок №6: строительство, верфи и модернизация

Статус: SOURCE-COVERED / CODE_UNVERIFIED (исходные алгоритмы Rust, не работающий собранный Godot).
Источник: archive/rust-galaxy-067-reference, SHA 6e40615be95cc6ddbabe21c3b94def5c52f8622d.
Резервация N154 создана первой записью в feature/godot-nightshift-20261112, commit 5e23453f. Соседний N153 занят другим чатом на макро №4 и не менялся.
Рабочая ветка: feature/godot-n154-construction-strategy-shipyard-refit-20261113.
Основа PR: integration/godot-47-n33-n37-20261112.

## Выявленная граница оригинальной игры

В frozen Galaxy Rust есть Shipyard ModuleStock, десять реально производимых модулей T2/T3, оплачиваемая работа экипажа верфи и платная замена корабельного оборудования. Есть административное создание корабля в sim_server/engine/admin.rs::admin_spawn_ship (N119). Но завершённой промышленной цепочки создания **нового корпуса корабля** по платному рецепту замороженный Rust не содержит. Не подменяем недостающую новую механику фиктивным Source-Covered портом; платные корпуса станут отдельной задачей после переноса, если будут нужны.

## Новые файлы и frozen source

1. n154_native_construction_strategy.gd — native/crates/sim_core/src/strategy/construction.rs::run_cycle, commissioning_supply:
   - Старейшие действительные незаконченные площадки рассматриваются до новых целей; target товара читается из source site-ID, даже если физический материал другой.
   - Источник shortage: MarketHistory.shortage_ticks >= 600 и original shortage_priority = age * (1 + preference[secure_commodity].clamp(0,2)).
   - Director colony chain: mining_rig (реальный Ice/Gas/Ore), refinery Water, farm Food, factory Electronics. Ни одна фабрика не создаётся бесплатно.
   - Реальные research/tiers T2 alloytech2 и T3 quantumtech3; редкие руды требуют соответствующих drill/survey технологий. N134 Director/mandate/charter authority передаётся через действительные факты, не выдумывается в N154.
   - Оригинальный лимит физических предприятий на ядро станции T1=4, T2=5, T3=6, проверка построенного, строящегося и конфликтующего чужого site, ресурсов планеты и BodyOrbit.
   - Source selection: нет закупки в том же рынке, торговля разрешена N150, реальные физические предложения >= quantity, местные по фракции источники первыми, затем меньшая цена и ID; ceil(price*actual_market_buy_multiplier*quantity) < 10000. Отсутствие реального N150 multiplier/commerce permission — отказ, не нейтральное значение из воздуха.
   - Реальный бюджет: treasury >= 30000 и стоимость всего проекта ceil(remaining/200)*10000 + 20000 startup + 150 labor <= treasury - 5000 floor.
   - Только новые площадки могут выбрать альтернативный физический recipe feedstock при отсутствии выгодного источника целевого товара. Сохранённую площадку и её commodity не переписывать.
   - Уже размещённый outstanding (включая Paid/Expired с reserved) contract препятствует двойному заказу, Shadow не мутирует, при Execute обязательно одобрение главы. Source экономический gate из N134/макро7.

2. n154_native_construction_commission.gd — strategy/construction.rs, faction::ensure_site_spawned_with_material, construction::refresh:
   - Реальный якорь FacilityIdentity+FacilityLocation, BodyOrbit.universe_position, точная callback facility_offset_position, ID site-target-location-tick, один site с material required 600, labor required 150 и событие construction_site_started.
   - При уже существующем site — проверить owner/material/location и повторно использовать; нельзя повторно начинать всю постройку.
   - Только после доказанного existence сайта и источника сформировать ОДИН prepaid Construction ContractBoard post через N104/N152: faction source, reward 10000 CR, quantity <= 200, mission strategy.construction.v1. Lifetime 800 * multiplier без Director или max(800, shortest_distance_graph * 100 + 1200) * multiplier с Director. Истинный WorldRegistry — N142, не расстояние по координатам.
   - Refresh показывает только истинный site material/labor progress, не фальшивое выполнение контракта.

3. n154_native_shipyard_module_tick.gd — native/crates/sim_core/src/agents/facility/mod.rs::tick_produce_modules:
   - Период один раз на 15 * multiplier ticks; один understocked модуль в порядке РОВНО 10 source recipes N132 на shipyard за один тик; потолок ModuleStock.count=2.
   - Только не abandoned shipyard и настоящий MarketIdentity в той же локации. Inputs вычитаются из MarketPricing.supply, не из выдуманных резервов верфи.
   - Input payment = ceil(sum(MarketPricing.price(commodity)*recipe.qty)), берётся из оригинальной MarketPricing/N131.
   - Перед выдачей модуля обязательно настоящий paid-shift от FacilityWorkforce::pay_shift (общая занятость, 1 CR на работника, producer и stock-owner of market, оплата настоящих входов). N39/макро1 владеет этим единым кошельком и реальным pay_shift. Только после внутреннего receipt о зарплате и полном input_payment — одна staged операция market supply decrease и ModuleStock.add_one; никакой бесплатной выдачи модуля.
   - Когда первый подходящий по материалам рецепт не может пройти оплату труда/сырья, Rust останавливается на этом рецепте, не перескакивает на более дешёвый.

4. n154_native_paid_shipyard_refit.gd — sim_server/src/engine/admin.rs:
   - try_shipyard_refit: правильный module slug/slot из единого оригинального N51 каталога, recipe N132, физический ShipPosition.docked_at именно на shipyard, реальный ModuleStock > 0 и ShipEconomy.credits >= module installation price.
   - apply_fitting_swap вызывает переданный исходный ShipFitting.set/recompute: ShipCargo.capacity = round(class_cargo_capacity * cargo_capacity_mult), ShipFuel.speed_modifier=class_base_speed * speed_mult, ShipLifecycle.dirty=true.
   - commit_shipyard_refit в том же эксклюзивном экономическом кадре: ModuleStock.take_one, ShipEconomy.credits debit, FacilityOperations.credits saturating_add(cost), событие ship_refitted. Отдельный admin_refit_ship без via_shipyard бесплатен как реальный source override (не продавать фальшивый модуль).
   - admin_refit_facility через единственный FacilityFitting catalog/rebake, без новой кассы.

5. n154_native_construction_materialize.gd — sim_server/src/engine/apply.rs::apply_construction_delivery/tick_construction_labor и engine/drains.rs::materialize_facility:
   - Настоящая delivery, уже оплаченная N104, увеличивает только progress_delivered (не больше remaining). Если site не найден, оригинал сливает физический груз в настоящий MarketPricing.supply destination; НЕТ второго расхода корабля или оплаты.
   - Labor tick cadence = 5 * max(mult,1), только работа реального N141 construction::labor::work. Завершить Site можно лишь после materials >= required и labor.completed >= labor.required. Никогда не создавать объекты только после доставки товаров.
   - Нормальная materialization использует source slug-ID, отрицательный DB ID из единого allocator, фактический location_id, BodyOrbit/position, default FacilityFitting и FacilityCrew через исходные owners, docking_capacity=4, market service, condition 1, reputation 50. Startup 20000 CR — строго из treasury (clamp(0,20000)), не новые деньги. Последняя оплаченная WorkShift копируется в новый FacilityCrew, а Site должен быть удалён в том же frame, что DB PendingMaterialization.
   - Colony Site с labor.colony_source НЕ создаёт ещё одну станцию: original engine/colony.rs::establish обновляет уже существующий dock/market. Владение макро2 N151 сохраняется.
   - Никакого прямого DB WRITE: макро10 сохраняет реальную transaction/journal в Phase2.

6. n154_construction_shipyard_source_checks.gd — сценарии настоящего выбора строек, treasury floor, Shadow/Head gate, продолжения site, source delivery fallback, paid shift, невозможности модуля без receipt, реального 8000 CR рефита, выдачи startup только из фракционных денег и сохранения рабочей смены. AUTHORED ONLY, NOT RUN.

## Источники, уже покрытые другими PR

- N75 PR #161, N77 PR #166: ConstructionSite, physically delivered materials, durable labor and read-only snapshot.
- N91 PR #179: agents/construction/executor.rs::utility/capable/target/active/present/offers/choose. Это точечный строительный executor, а не общий Ship BT. Другой чат резервировал N153 на полный автономный ИИ №4.
- N141 PR #229: agents/construction/labor.rs, paid 150-worker units, real population/faction accounts, 60% workforce availability and shared per-tick occupancy.
- N132 PR #221: economy/module_production.rs canonical ten T2/T3 recipes.
- N51 PR #141: native modules CATALOG / ShipFitting source.
- N110 PR #198, N143 PR #233: source progression/research/real station tiers.
- N119 PR #208: administrative ship spawn/hydration, NOT hull crafting.
- N104 PR #193 + N152 PR #241: true prepaid construction delivery, Board / escrow / contract statuses.
- N142 PR #231: true WorldRegistry shortest_distance, N150 PR #239: market controller/treaties/price multiplier.
- N134 PR #223: Head decision and constructor authorization, macro7 overall strategy still open.

## Интеграционные границы и честный статус

Это SOURCE-COVERED список существующих Rust строительных/верфевых source slices, НЕ работающий standalone Godot. Реальная последовательность Phase2: N134 Head approves -> N154 Strategy -> N154 Commission -> one N104+N152 paid Board + real ECS Site -> N135 real carrier -> N104 physical receipt -> N154 Material progress -> N141 real labor shift with shared N39 workforce -> N154 Materialization + N10 durable DB frame. Module branch: N132 recipe -> N154 yard plan -> actual N39 paid labor+market owner credit -> N154 ModuleStock -> N154 refit -> N51 fitting rebake and one ship-to-yard credit commit. Один источник денег и единая занятость; исторические N17/N75/N77/N91/прочие не запускать как отдельные параллельные Economy ticks.

Risks for Phase2: Rust f32 versus GDScript f64 around strict ceil/round and prices; extreme u64/i64 and Unicode slug identities (N154 fails closed for unsupported Unicode), truly deterministic Rust HashMap ties, external N39 paid payroll receipts. New data-only scripts have no Godot parser/headless/runtime evidence, no Rust executable replay, no merged PR or real world state; record CODE_UNVERIFIED. Complete hull production is intentionally absent from source and not claimed as implemented.

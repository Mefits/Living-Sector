# N39 — физическое производство / оплаченные смены WorldBridge (макроблок №1)

**Фаза 1, SOURCE PORT / CODE_UNVERIFIED.** Резервация N39 передана первому чату 2026-11-13 по прямому подтверждению пользователя: предыдущие чаты выключены. Старый branch N39 имел zero commits относительно базы и не содержал самостоятельного PR. Handoff зафиксирован в `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N39.json`.

**База Godot:** `integration/godot-47-n33-n37-20261112@1e4a1e9`.
**Замороженный источник:** `archive/rust-galaxy-067-reference@6e40615`.
**Рабочая ветка:** `feature/godot-n39-production-worldbridge-20261112`.

## Состав N39

| Файл Godot | Источник Rust / поведение |
|---|---|
| `n39_native_world_schema.gd` | FacilityIdentity/Location/Operations, MarketIdentity/Pricing, PopIdentity/Demographics/Economy, BodyIdentity/Resources — настоящие идентификаторы собственника, место, кошелёк и конечные stock. Не создаёт сущности из воздуха |
| `n39_native_paid_shift.gd` | `agents/facility/workforce.rs::pay_shift/commit_shift/occupied_workers/refresh_employment`. Работники — локальные реальные Pop, max 60% от каждого Pop, общий учёт занятости + внешние подтверждённые work shifts, зарплата 1 CR/worker, source processing owner case (владелец stock дебет wages+ceil(wages/10), производитель получает комиссию), `WorkShift` и paid receipt, одно выполнение за тик. Для paid repair можно передать `input_payment=0`. Работает через единственный локальный экземпляр существующего N9 `credit_ledger.gd`, а не собственную реализацию ledger |
| `n39_native_world_production.gd` | `agents/facility/mod.rs::tick_recipes_and_mining`, `level_scaled_max_batches`, `grant_facility_xp`, `salvage_extraction`, `economy/recipes.rs`. Общий рынок местоположения, N73 14 рецептов, 5×mult интервалы, исходные технологические gate, исходный market price profitability, ферма Food cap 5000 c дробным финальным batch, лимит базовых 20 batches +0.2 per level +модули и реальные Director технологии, эффективность экипажа, T2/T3/retrofit, реальный paid wage до изменения stock, источник доказательства последнего выполнения каждого рецепта в `WorkShift`, XP только после реального оплаченного выпуска, обычная добыча 80 × richness × efficiency без depletion, отдельная конечная salvage с делителем 3 и 8000 units/richness |
| `n39_native_production_tick_runner.gd` | Опциональный `tick_runner.gd` adapter: `bodies` → `facilities` в правильном source phase, не пропускает N1 события/calendar/signal, checkpoint preflight. Не меняет N23 демонстрационный runner и не делает full Phase2 world engine |
| `n39_source_regression_checks.gd` / `n39_headless_entry.gd` | Проверки реального рынка/зарплат, market owner service fee, workforce shortage, insufficient cash, farm fractional limit, mining, salvage depletion, tech, replay, restore. Написаны, **не выполнены** |

## Взаимодействие с другими owner-модулями

- N6/N8/N23 `paid_production`/`production_coordinator` были ограниченными opt-in demo shifts (один рецепт и snapshot-аккаунты) и **не должны запускаться вместе** с N39. N39 используют те же N9 Ledger, Inventory и N73 `native_recipes`; нет второго авторитетного расчёта фракционных денег в общей игре.
- N156 [PR #244](https://github.com/Mefits/Living-Sector/pull/244): condition decay, dock queue, crew morale, paid repair, abandonment, supply+convoys and 9 crew missions. **Не скопировано.** По Rust `facility/mod.rs` N156 и N39 выполняются последовательно одним future Phase2 TickCoordinator.
- N130 service restock, N104/N152 Board and prepaid contracts, N132/N154 paid shipyard modules, N107 station plan/feedback, N143 Director tech, N110 fittings, N140 AgentLod, N141 construction labor, N139 chain planning — отдельные source owner.
- При финальном объединении **нельзя** выполнять N39 local `lod_next_tick` отдельно от N140 cursor или заводить дополнительный `CreditLedger` рядом с runtime. Выбрать единственный N140 gate, единый N9 ledger и один Market/Pop/Facility world. N39 snapshot получает на вход уже истинные данные этих владельцев; интеграция в общий ECS оставлена на Фазу 2.

## Source conditions, которые недопустимо терять при сборке

1. Весь `MarketPricing.supply` физически принадлежит *одному* market entity по location. Facility payer и владелец рынка обязаны иметь одинаковые faction+location.
2. Payroll платится только после успешного dry-run всех recipe candidates или material extraction. Нет зарплаты за пустой результат, нет stock за отклонённую зарплату; один `WorkShift` per facility per tick и только один receipt.
3. При owner==producer платит сам производитель. При другом владельце рынка платит owner зарплаты и сервисную комиссию, producer получает комиссию. Для платного input purchase отдельный `Some(cost)` режим.
4. Исходная физика mining: обычная mining rig **не** истощает `BodyResources`; salvage-field истощает конечный body cache, и только после оплаты. `rare_ore` требует survey2+drilltech2, `crystal_ore` survey3+drill3.
5. `WorkShift.last_recipe_ticks` и `produced_outputs` — только фактически оплаченный рецепт; его нельзя подменить записью `wages` без physical output.
6. Factory/refinery Tech&FacilityFitting bonuses получают из уже существующего N143/N110 состояния; no default unlocks. При `StationAdministration.executing` необходимая allocation >0.
7. Внешние оплаченные N141/N143 смены необходимо передавать как уже проверенные `external_workers` перед physical shift, чтобы не занять одного и того же жителя дважды.
8. Rust `f32` stocks и `f64` intermediate не гарантируют побитового совпадения с GDScript float64. Фаза 2 должна сравнивать числовые паритеты в допусках и source f32 rounding, проверить реальный `htn`/event runner отдельно. Тестовый перезапуск Godot и Rust reference **не проводился**.

## Ручной запуск при наличии Godot 4

`godot --headless --path godot --script res://scripts/sim/phase1/n39_headless_entry.gd`

`n39_headless_entry.gd` запускает source probes и возвращает exit code 1 при ошибке. Сейчас только GitHub readback и статические проверки. **Нет основания утверждать, что Godot парсер или игровой tick проверены.**

## Закрытие исходников vs готовность игры

N39 завершает ранее открытые в макроблоке №1 source-функции реального производства, добычи, payroll и XP. Вместе с N156/N130/N154/N73/N141 и др. исходный домен экономики может быть обозначен **SOURCE-COVERED / CODE_UNVERIFIED**, *после сверки свежих claims и полного source inventory*. Это не означает, что Phase2 интеграция, сервисные переходы ECS, persistence и executable runtime уже выполнены. Модуль №7 N100 параллельного второго чата не затрагивался.

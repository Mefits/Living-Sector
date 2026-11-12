# N149 — макро №3 «Корабельная жизнь»: ЗАКРЫТО исходное покрытие Rust, но НЕ подтверждено в Godot

**Результат Фазы 1:** исходное покрытие **SOURCE-COVERED** по компонентам, эффектам и интерфейсу корабельной жизни `ShipCrew / ShipLifecycle / ShipProgression / ShipFitting / ShipCargo / ShipFuel / read-only ShipSnapshot` из frozen `archive/rust-galaxy-067-reference`. Это критерий *переноса исходной механики по самостоятельным GDScript-компонентам*; **ни один черновой PR сам по себе не является рабочим игровым циклом**, и на дату N149 нет доказанного Rust↔Godot replay.

**Резервация до кода:** `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N149.json`, commit `80f203d7`; рабочая ветка `feature/godot-n149-ship-crew-full-parity-macro3-closure-20261113`. Оригинальные Rust-файлы и Godot-integration baseline не менялись.

## Критический пробел, который закрыл N149

Уже существующие переносы **N72 / PR #164** и **N138 / PR #228** оба описывают части `native/crates/sim_core/src/agents/ship/mod.rs::tick_crew`, но **их невозможно просто последовательно вызвать** без нарушения порядка Rust:

1. **Decay:** hunger растёт `1.0 × tick_scale × skipped_LOD_ticks` или уменьшается `5.0×` на станции; fatigue зависит от *старой* задачи Resting(-5), Idle вне полёта(-1), docked(-5), active(+0.4), с source priority.
2. **Morale** каждые `5×mult` тиков по **уже изменённым** голоду/усталости и **старой** задаче; отдельные docked health, off-station hunger/fatigue/health penalty, отдыхающий/док recovery (+8/+6), drift ±0.5 к 50.
3. **Food + task:** при `hunger >55` нужно купить/съесть `crew.size×1 Food` именно из реального ShipCargo (без Food — всё равно Eating), убрать `cargo.cargo_age[Food]` при исчерпании; голод уменьшается на 25. При `fatigue >65` Resting; иначе conditional source `primary_task` roles (pilot/engineer/trader), с сохранением strict `<` при выходе из Eating/Resting.
4. **Wages** каждые `50×mult` тиков: ровно `size×5` CR из существующего `ShipEconomy.credits` в существующий `ShipCrew.wages_credits`, при возможности `i64.checked_add`; иначе **-5 morale**, без выдачи невыплаченных денег.
5. **Efficiency** В КОНЦЕ, с учётом *последнего* штрафа за невыплату: `clamp(health/100*0.6 + morale/100*0.4,0.1,1.0)`. Dirty-настройка только для экипажа.

N72 делает физическую еду/зарплату в одном самостоятельном `step`, но не синхронизируется по морфазе/полной ролевой логике N138. **N149 `n149_native_crew_tick_single_owner.gd` переносит весь `tick_crew` ровно в исходном порядке в ОДНОМ чистом полном proposal.** Он не применяет физические эффекты, но представляет одну полную порцию `before`, `projected_ship`, `effects` для будущей **единственной** транзакции реального ECS. **В Фазе 2 N72.step + N138.batch + N149.core_step одновременно ВЫЗЫВАТЬ ЗАПРЕЩЕНО**. N72 и N138 остаются историческими source fragments/reference, authoritative per-ship step выбирается N149 и уже использует их ранее перенесённые инварианты. Двойных бухгалтерских записей и Food-списаний не появляется.

Новые N149 файлы: `n149_native_crew_tick_single_owner.gd` (full 5 phases + LOD fired batch), `n149_native_ship_components_basics.gd` (точные `ShipCargo.used/free` и `ShipFuel.fraction`), `n149_native_crew_tick_checks.gd` (позитивные/негативные сценарии из источника, **написаны, не запускались**).

## Итоговый source audit macro №3

| Frozen Rust source / функция | Подтверждённое покрытие GDScript | Граница компетенции |
|---|---|---|
| `ship/components.rs::ShipCrew`, `ShipCrewSkills` агрегатные значения/состав экипажа; первичные роли | N50 [PR #139](https://github.com/Mefits/Living-Sector/pull/139), N128 [PR #217](https://github.com/Mefits/Living-Sector/pull/217) | Никаких индивидуальных crew entities; Elixir `CrewComplement` остаётся агрегированным |
| `ship/mod.rs::tick_crew` 5 исходных шагов, `primary_task`, food+payroll физические расходы, morale/efficiency | N72 [#164](https://github.com/Mefits/Living-Sector/pull/164) (исторические физические фрагменты), N138 [#228](https://github.com/Mefits/Living-Sector/pull/228) (morale/tasks), **N149 — единственный полный source step** | Одна авторитетная future engine transaction; N72/N138 не вызывать повторно |
| `ship/components.rs::ShipCrew::efficiency/needs_shore_leave/shore_leave_complete`, `CrewTask::as_str` | N138 [#228](https://github.com/Mefits/Living-Sector/pull/228) + N149 + N148 wire | Не внедрять вторую динамику морали; no damage system live in frozen Rust |
| `ship/components.rs::ShipCargo::used/free`, `ShipFuel::fraction` | **N149 native_ship_components_basics.gd** | Отдельные действия покупки/продажи/заправки принадлежат **макро №5** |
| `ship/components.rs::ShipProgression::new/next_level_threshold/grant_xp/spend_retrofit_point` | N101 [PR #189](https://github.com/Mefits/Living-Sector/pull/189) | XP/retrofit point только после реальных delivery/refit apply receipts |
| `ship/components.rs::ShipFitting::{new_default,new_for_size,from_slugs,set,recompute,slot_slug}` / `sim_core/modules/*` | N51 [PR #141](https://github.com/Mefits/Living-Sector/pull/141) и N101 [#189](https://github.com/Mefits/Living-Sector/pull/189) | Реальные оплаченные refit transactions принадлежат макро **№6** и №5 |
| `ship/components.rs::ShipLifecycle` + `ship/behavior.rs` собственно idle/strike/retirement slice | N148 [PR #237](https://github.com/Mefits/Living-Sector/pull/237) | БТ/цели/автономный поиск контрактов принадлежат **макро №4** |
| `ship/mod.rs::tick_ships` LOD gate и `advance_transits` | N140 [PR #230](https://github.com/Mefits/Living-Sector/pull/230) + N40/N112, N59–N61 | Единый живой tick scheduler и интеграция всех фаз — **Фаза 2**, цель/БТ — макро №4 |
| `ship/snapshot.rs::ShipSnapshot::build` + реальный crew UI и lifecycle | N148 [#237](https://github.com/Mefits/Living-Sector/pull/237) и N67 [#156](https://github.com/Mefits/Living-Sector/pull/156) | HTTP/WS — READ ONLY, не source-of-truth и не save |
| Persistent ship checkpoint, initial credit source, fitting & crew state | N54 [#144](https://github.com/Mefits/Living-Sector/pull/144), N50, N51, N52 [#142](https://github.com/Mefits/Living-Sector/pull/142) | **Макро №10** — глобальная DB save/replay/restore consistency; not ship-specific welfare algorithm |

### Не считать незакрытой «корабельной жизнью» соседние исходники

- `ship/behavior.rs`, `ship/actions.rs`, `ai/personality.rs`, `ai/behavior_tree.rs` — полноценный **автономный корабельный ИИ (макро №4)**. Там находятся goal/replan/BT, docking/rest action timeout, exploration/trade/mining/contract/refit decisions, цена и память. Условия shore-leave из N138 перенесены; actual choice/execution остался у owner макро №4.
- `ship/components.rs::ShipAI,ShipMemory,ContractRejection,RouteStats`, `ship/mod.rs::observe_prices` — состояние/память и ценовая разведка **макро №4/9**; часть уже в N80/N83/N103/N137, и source gap этих стратегических алгоритмов **не следует скрывать** под закрытием №3.
- `ship/transactions.rs` и непосредственная cross-entity оплата, Cargo/Market Transfer, Deliver/Accept/Refuel — **контракты и физическая логистика (макро №5)**.
- `ship/behavior.rs::DecommissionShip` собственная lifecycle оценка и `engine/drains.rs` жизненный цикл списания уже вошли в N148; настоящая серверная DB-очистка и spawn_replace ответственность exclusive server/world owner **Фазы 2/макро №10**, не дублированная запись N149.

## Критерии и ограничения итогового закрытия

**SOURCE-COVERED №3** означает: для каждого существующего алгоритма собственно **корабельного жизненного цикла** из frozen Rust есть конкретная GDScript реализация и передача зависимостей, включая теперь строго последовательную физическую смену. Не означает, что Godot сейчас действительно списывает корабли, выплачивает зарплаты, выращивает навыки и отражает мораль в UI. Последнее требует **Фазы 2**: собрать ряд раздельных draft PR в один `World`, сохранить тождественность source owners, соединить LOD→transit→crew→AI→apply, выполнить тесты на Godot 4 и Rust↔Godot parity, проверить DB snapshots/save/replay и реальную экономическую сохранность.

**Неснятые технические риски**:
1. Rust считает часть изменений в `f32`, а GDScript `float` — `f64`; пороговые и долговременные расхождения должны быть проверены в Phase2. Новых регуляторов нет.
2. Токен `trusted_internal_apply`/соответствие словаря не доказывает реальную транзакцию: настоящий exclusive engine может предоставить его только **после** сравнения исходных snapshot preconditions и единого реального применения `ShipCrew,ShipCargo,ShipEconomy`. Прямой публичный вызов N149 или отдельный N72 по этим данным не является оплатой.
3. N149 fixtures созданы в GDScript; **НЕ ЗАПУСКАЛИСЬ**, нет parser/headless/Windows, не выдавать CODE_UNVERIFIED за VERIFIED.
4. Rust является эталоном для исходной механики (включая legacy morale). Любое удаление/балансировка такого наследия после полного переноса согласовывается отдельно, не в Фазе 1.
5. В коде N149 закрывается **source mapping №3**, а не критерия 100% всего проекта: остальные макро #1/2/4/5/6/7/9/10 требуют реальных source ports, а №8 уже source-covered.

**Статус:** `MACRO3_SOURCE_COVERED / CODE_UNVERIFIED`; два из десяти направлений с полным исходным покрытием (#3 и #8), восемь направлений имеют ещё source gaps. Глобальный остаток Фазы 1 необходимо оценивать по реальной исходной инвентаризации; он **не** равен `8/10 = 80%` объёма оставшейся работы и не уменьшается механически за каждый PR.

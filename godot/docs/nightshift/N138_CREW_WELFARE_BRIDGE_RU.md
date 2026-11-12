# N138 — корабельная жизнь: мораль, задачи и эффективность экипажа

**Статус:** `CODE_UNVERIFIED`, самостоятельный компонент Фазы 1 (без запуска Godot и без интеграции).

## Эталон и границы

Замороженная Rust Galaxy 0.6.7:
- `native/crates/sim_core/src/agents/ship/mod.rs`: crew constants 228–320; `tick_ships` LOD/phase order 349–445; `tick_crew` 456–639; `primary_task` 642–668.
- `native/crates/sim_core/src/agents/ship/components.rs`: `ShipCrew`, `CrewTask`, `ShipCrew::efficiency` and shore-leave gates 364–436.

**Не создаём второй N72.** N50/PR #139 и N128/PR #217 отвечают за создание экипажа и навыки; N72/PR #164 уже переносит агрегатный голод/усталость/настоящие затраты еды/зарплаты, но не охватывает полный Rust-порядок морали и заданий и пока не подключён к живой игре. N88/PR #177 отвечает за действие Rest/докинг, N80/PR #169 — за стратегический replan. Их файлы не менялись.

Новый код:
- `godot/scripts/sim/phase1/n138_crew_welfare.gd`: точная чистая логика `morale_after_decay`, `task_after_meal`, `primary_task`, `efficiency`, береговые и Rest-пороги, native dock-wait metadata.
- `godot/scripts/sim/phase1/n138_crew_welfare_batch.gd`: многокорабельный детерминированный staged batch с сортировкой ship id, полным отказом при недостоверном снимке. **Не выполняет ни одной реальной экономической транзакции.**
- `godot/scripts/sim/phase1/n138_crew_welfare_checks.gd`: проверки, подготовленные по Rust; на Фазе 1 НЕ запускались.

## Важный порядок за один общий tick

Сохранить существующий главный цикл `tick_ships`: LOD gate → transit → price observations → crew → decision/actions. Только корабль в наборе активных LOD тиков вообще проходит `tick_crew`; effective scale = `tick_scale * skipped_ticks`. **N138 не пытается повторно вычислить LOD или голод: принимает из актуального снимка значения уже после decay N72.**

Внутренний Rust tick_crew:
1. **N72 decay**: hunger и fatigue на `effective_scale`, с учётом in_transit/docked и текущего task.
2. **N138 BEFORE MEAL**: каждые `5*multiplier` тиков — morale penalty/recovery/drift; важно: проверка до съедания еды. При доке penalty -2 только при health<50, иначе ноль; вне дока hunger>60 даёт -3 и имеет приоритет над fatigue>70 (-2), затем health<50 (-4). Docked+resting +8, docked или недокированный resting +6; drift +0.5 при morale<=50, иначе -0.5.
3. **N72 food**: реальное `Food >= crew.size * 1`, дебет cargo и cargo_age как в Rust, уменьшающий hunger на 25 только при факте еды. Нельзя дважды исполнять N72 `step`.
4. **N138 AFTER MEAL**: выбрать Eating при `hunger>55`, Resting при `fatigue>65`; выход из Eating/Resting только при **строго** `hunger<55` и `fatigue<65`. Idle или transit не-Piloting вызывает refresh по `primary_task`: в пути pilot → engineer → trader → idle; без полёта trader → engineer → idle.
5. **N72 wages**: каждые `50*multiplier`, реально `5 * crew.size` со счета ShipEconomy в `crew.wages_credits` или -5 morale при нехватке/overflow; никаких бесплатных денег и повторной выплаты.
6. **N138 AFTER WAGES**: `ShipEconomy.efficiency = clamp(health/100*0.6 + morale/100*0.4, 0.1, 1.0)`; `ShipCrew.dirty=true`.

**Ключевое условие Фазы 2:** существующий `N72.native_crew_upkeep.step` выполняет шаги 1,3,5 в одном методе и дополнительно имеет собственные урезанные morale/task правила. Чтобы не получить двойное восстановление и неправильный порядок, интеграционный адаптер **должен разбить N72 на чистые оригинальные этапы**, удалить только старые упрощённые morale/task пути и вставить `N138 Batch.before_meals/after_meals/after_wages` между ними. Нельзя просто вызывать целиком N72.step и затем N138 batch. До создания такого адаптера N138 остаётся НЕПОДКЛЮЧЕННЫМ.

## Входной контракт

`Batch.before_meals(post_decay_ships, tick, multiplier)`, `Batch.after_meals(post_food_ships, tick, multiplier)`, `Batch.after_wages(post_pay_ships, tick, multiplier)`.

Снимок — Dictionary `ship_id -> {crew, economy, roles, in_transit, docked}` с настоящим `ShipCrew`:
`crew={size, hunger, fatigue, morale, health, wages_credits, current_task, dirty}`.
`economy={credits, efficiency,...}`. `roles` из `simulation/config.rs::ship_class().crew_roles`, а `docked` из реального `ShipPosition.docked_at`; не выводить его из наличия location. `current_task` — Rust snake_case, пустой/неизвестный тип не считается Idle. Stage returns `{ok, reason, ships, phase}`; если один корабль испорчен, **ничего не менять у всех**.

Ни один метод N138 не трогает `crew.size`, `wages_credits`, `economy.credits`, `cargo` или world. N138 `status` только читает; наблюдение не создаёт фактических актов еды/оплаты и не доказывает выполненный контракт. Моральный threshold для `needs_shore_leave` — <50, complete — >=100, legacy rest planner trigger — <15, Rest success — >=80. Числа ожидания дока 150/60/30, timeout rest 300 — лишь параметры из Rust; не подменяют реальное выполнение BT из N88.

## Проверки / незакрытое

GitHub source readback, статическая балансировка скобок, проверка путей `res://` без запуска движка. Проверочный сценарий задаёт последовательность penalty, Dock/Rest восстановление, границы task, проверки purity/без повторных выплат и атомарный отказ при некорректном втором корабле. **Нет реального успешного Godot parser, runtime или Rust test parity evidence**. В Фазе 2 нужны адаптер очередности (и типовые преобразования), проверка Rust f32 против Godot float на границах, replay-safe authoritative tick checkpoint, запуск Godot. Фаза 3 Grok позже.

# N80 — автономная политика выбора целей корабля (Rust → GDScript)

**Фаза:** 1 — покомпонентный перенос оригинальной Rust Galaxy 0.6.7.  
**Дата:** 12.11.2026.  
**Статус:** `CODE_UNVERIFIED` — перенос исходной **оценки и арбитража решений**, не готового исполнения всех ShipAction. Godot не запускался по утверждённому плану.  
**Резервация:** `feature/godot-nightshift-20261112:godot/docs/nightshift/claims/N80.json`.  
**Рабочая ветка:** `feature/godot-n80-native-ship-decision-ai-20261112`, база `integration/godot-47-n33-n37-20261112`.  
**Запрет пересечения:** N39 production, N78 faction director, N77 construction, N79 colony, P1/main/stable.

## Реальные замороженные Rust-источники

1. `native/crates/sim_core/src/ai/personality.rs` — шесть осей личности, 10 архетипов (7 для random_ship, 3 для random_crew), приоритеты целей, дрейф осей и variation ±0.1 с округлением до двух знаков. Существующие seeded ship personalities в Rust порождаются RNG и **НЕ** выводятся из класса корабля. `Personality::for_class` — только fallback/админский спавн.
2. `native/crates/sim_core/src/ai/utility.rs` — аддитивные положительные/отрицательные факторы, целевой бонус `prefer_goals`, `best_action` выбирает строго лучший результат, равные оставляет в исходном порядке; `rank_actions` сохраняет стабильный порядок равных значений.
3. `native/crates/sim_core/src/ai/considerations.rs` + `agents/ship/mod.rs` — физический остаток топлива, товарное заполнение, финансовое давление, стремление к исследованию и свежесть цен `2^(-age/1500)` с нижней границей 0.10. В частности, `ShipFuel::fraction()` в `agents/ship/components.rs` при нулевой вместимости возвращает **0**, а не 1.
4. `native/crates/sim_core/src/agents/ship/behavior.rs` — `plan_goal`, `score_strategic`, `is_replan_eligible`, `decide_and_act`, `smart_idle_fallback`, `profitable_mining_quantity` и `choose_ice_mining_trip`; исходные коэффициенты и условия из той же ветки.
5. `native/crates/sim_core/src/agents/ship/components.rs` — `CREW_REST_TRIGGER=15`, `IDLE_EXPLORE_TICKS=240`, `EXPLORE_MIN_CREDITS=2500`, `EXPLORE_MIN_FUEL_FRACTION=0.4`; `agents/facility/mod.rs` — `SALVAGE_UNITS_PER_RICHNESS=8000`.

## Перенесено в GDScript

Все файлы независимы от SceneTree, не вызывают UI и не меняют игровые деньги/ресурсы/корабли:

- `scripts/sim/ships/ai/native_personality.gd` — все исходные архетипы, `for_class`, чистый drift, вариация **только по переданным настоящим RNG draw**, чтобы не заменять Rust-сейдер придуманными личностями.
- `scripts/sim/ships/ai/native_utility.gd` — Rust additive scorer и best/rank с правильным порядком равных кандидатов.
- `scripts/sim/ships/ai/native_considerations.gd` — нужды, угроза по кредитам, cargo, price knowledge, честное затухание наблюдений, исследования.
- `scripts/sim/ships/ai/native_ship_goal_policy.gd` — весы групп `bio=100`, `housekeeping=40`, `strategic=3`, `explore=6`, `idle=0.5`, наступление срочности топлива `0.45`, потребности экипажа `15`. Контракты по приказу станции обходят коммерческие предложения, но срочный отдых/топливо остаются конкурентами. Реальный buyer/contract/trade/retrofit передаётся **как результат уже проверенного источника**, а не выдумывается скриптом. Стратегический заработок оценивается `ln(profit) * (1 + preferences + contested_bonus) * max(profit_axis, .3) * 3`.
- `scripts/sim/ships/ai/native_ice_mining_policy.gd` — экономическая добыча льда: `min(40, free_hold, physical_ice, buyer_liquidity)`, реальные цены, стоимость топлива **как оценка**, а не моментальное списание; возвращение уже добытого льда через фактический док. При равенстве предпочтение ближнему месту и лексикографически раннему site. Действия возвращаются как `ShipAction`-подобный **intent**, не исполняются.
- `scripts/sim/ships/ai/native_replan_policy.gd` — запрет срыва биологических/бытовых планов, минимум 40 тиков, проверка каждые 40 тиков со смещением из полного 64-битного FNV-1a hash ship ID; критерий переключения 1.30×, с текущим контрактом 1.80× + 0.5×loyalty. Опасное `ReleaseContract` не исполняется спекулятивно: формируется намерение для позднейшей Apply-фазы.
- `scripts/sim/ships/ai/native_ship_idle_policy.gd` — 240-тиковый порог исследования с поправкой на личность/банкротство, min fuel 0.40, min credits 2500; иначе путь к реальному доступному доку или idle. Выбор доступных систем/доков должен предоставить authoritative `WorldRegistry`.

## Что НЕ объявляется перенесённым этим блоком

Нативный `behavior.rs` включает ещё: поиск **реально** выгодных контрактов и перевозок (`try_plan_contract`, `try_plan_trade_run`), `best_trade_route` с памятью цен, определение доступной модернизации, `pick_rest_destination` с загрузкой доков, `try_build_explore_bt` с обходом шлюзов и недавних систем, разные GOAP catalogs и BT `build_*_bt`. Их **не следует считать готовыми по N80**; это последующие блоки первой фазы. Исполнитель команд `agents/ship/actions.rs` и `ai/planner.rs` также требует собственных переносов.

Скрипты N80 принимают подтверждённые кандидаты и возвращают решение/очередь **только для будущего соединения в фазе 2**. Запрещено передавать `feasible=true` без авторитетной проверки физической логистики, доступных денег/ресурсов, репутации и маршрутной возможности.

## Быстрая проверка без запуска Godot

- Файлы источников Rust прочитаны, коэффициенты и названия условий сопоставлены.
- 64-битный FNV-1a посчитан по двум 32-битным частям без надежды на переполнение int GDScript; для четырёх ship ID произведена независимая сверка с точной BigInt u64 моделью: результаты совпали.
- Проверяются синтаксически очевидные ошибки и наличие `res://` preload путей, без отдельного headless/Windows теста в фазе 1.
- **Не подтверждено:** реальная загрузка Godot, совместимость всех типов GDScript и фактическое исполнение AI-событий.

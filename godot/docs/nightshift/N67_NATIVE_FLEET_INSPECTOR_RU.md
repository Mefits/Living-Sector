# N67 — read-only наблюдатель настоящего флота

**CODE_UNVERIFIED**, отдельный PR поверх N66/N64/N61. Никаких UI-изменений в пользовательском P1 и никаких тестов на Windows до полного переноса.

- `scripts/sim/ships/native_fleet_observer.gd` читает **один живой авторитетный N66/N64 runtime**: ship state N14/N46, N21 dock, N11 ledger, N63 route intents и source-backed **стартовые** роли N50. Вывод отсортирован по native provisional ID, без создания SceneTree nodes.
- Для каждого корабля возвращает класс/фракцию/систему, место или реальный полёт, destination, занятость дока, fuel/fuel capacity, cargo/capacity, ship credit account, сумму экипажа и следующую промежуточную точку.
- Причины: `in_transit_until_actual_arrival`, `undock_required_before_departure`, `no_assigned_route_intent`; при нулевом топливе **не объявляет остановку**, потому что frozen Rust действительно продолжает движение (исправление N65 PR #154 потребует отдельной интеграции).
- Полей `crew_current_efficiency`, `crew_current_morale`, `crew_wages_paid`, `cargo_trade_profit`, `production_stats`, `live_ai_decisions` пока нет у действующего мира. Выводится явное **«—»**, никаких вымышленных чисел; нельзя выдавать стартовые навыки за текущую статистику.
- Fail-closed если DockingRegistry и ShipState расходятся, обнаружены неизвестный кредитный счёт, невалидный трюм или топливо. `snapshot` не меняет игровые значения, фазы или деньги.
- `tests/n67_native_fleet_observer_check.gd` использует native seed: 24 стартовых корабля, 2 760 000 кредитов в общей бухгалтерии, source-only поля, физическую доковку и полёт. Godot headless тест пока не запускался.

Этот компонент можно будет отдать панели Observation/Inspector после завершения основного переноса и интеграционного тестирования; сам отображение не рисует, точечные тесты от пользователя не требуются.

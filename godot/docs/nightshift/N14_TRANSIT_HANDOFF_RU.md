# N14 — движение корабля по направленному маршруту

**Статус: CODE_UNVERIFIED.** Рабочая ветка основана на N13 (PR #95), который основан на N4 (PR #92); не выполнять merge без проверки зависимостей.

Источники: замороженный Rust `native/crates/sim_core/src/agents/ship/mod.rs` (SHIP_BASE_VELOCITY=0.05, SHIP_ARRIVAL_THRESHOLD=0.01, step=velocity.min(dist), arrival on distance threshold, fuel consumption per tick), `agents/ship/components.rs` (Transit: from/to, departure_tick, display-only arrival_tick, distance_total/travelled). Ship class fuel/speed from `simulation/config.rs`.

Срез: проверка **направленного** ребра N4 перед стартом; положение от авторитетного resolver в world coordinates, не из N4 route weight; пошаговое продвижение с class/size speed и tick_scale; реальный расход ship fuel только во время шага; прибытие по физической дистанции, не по ETA; одноразовое применение тика; snapshot N13 сохраняет flight state; токен отменяет устаревшее событие прибытия. Принудительной мгновенной стыковки нет: прибытие означает location_name, docked_at остаётся неустановленным. Услуги станции, gate fee, рейсы через несколько рёбер и refuel — следующие блоки.

**Ограничения:** координаты динамических орбитальных целей поставляет вызывающая симуляция; маршрутные веса `travel_routes.distance` не объявляются мировыми единицами. Для полного Rust-паритета требуется интеграция native position resolver и тикового движка, проверка отсутствия топлива/аварийной буксировки, затем тест в Godot. Никакой склад/денежная операция здесь не происходит. Использованы штатные `RefCounted`, `Dictionary`, `Vector2`, без тысячи Node2D и без стороннего ECS. Godot docs: https://docs.godotengine.org/en/stable/classes/class_vector2.html ; https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html ; Game Programming Patterns Data Locality: https://gameprogrammingpatterns.com/data-locality.html .

Тест (не запускался):
```sh
godot --headless --path godot --script res://tests/n14_transit_check.gd
```

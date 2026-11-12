# N2 — календарь без подмены единиц Rust

**Статус: CODE_UNVERIFIED.** Godot Runtime не запускался.

Сверка: `native/crates/sim_core/src/simulation/config.rs` в `archive/rust-galaxy-067-reference` задаёт `ticks_per_second=8`, `world_speed=0.25`, `tick_scale=world_speed/ticks_per_second`. Это **не** утверждение, что один native unit равен игровому часу. Текущий `SimCalendar` аккумулирует только фактически исполненные шаги и не использует render FPS. Орбиты продолжают использовать исходный `tick_scale`.

Решение: лёгкий `RefCounted` без Nodes, `TickRunner` — единственный владелец; UI получает только форматированную проекцию. Готовые инструменты Godot: `RefCounted`, `FileAccess`, `JSON`, `Control`; сторонний календарный плагин не нужен. Паттерны: [Game Loop](https://gameprogrammingpatterns.com/game-loop.html) и [Event Queue](https://gameprogrammingpatterns.com/event-queue.html); для N3 планируется детерминированная очередь. [Godot idle vs physics processing](https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html) объясняет, почему UI FPS не должен определять экономику.

Сделано: счётчик native units; явно отключённая по умолчанию конверсия в игровые часы; текст календаря в статусе; checkpoint/restore с атомарной проверкой; старые v1 сейвы без календаря загружаются, но историческая длительность помечается неизвестной (не восстанавливается ложной формулой); smoke для разной группировки кадров, ошибок restore и legacy save.

Ограничение: текущий накопитель float — промежуточный, не годится как окончательная точная шкала для 1000-летней симуляции. N3 должен выбрать целочисленный fixed-point SimTime и определить единицу после аудита периодов Rust. `world_speed` в Rust меняет не только скорость отрисовки, но и native delta; поэтому нельзя заявлять одинаковое состояние при одинаковом количестве тиков, но разной скорости. Тест фиксирует равенство при одинаковой последовательности native delta.

Локальная проверка утром: `godot --headless --path godot --script res://tests/n2_calendar_check.gd` и существующий `p1_tick_save_check.gd`. Ни один из них в этой среде не запускался.

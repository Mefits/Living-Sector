# N79 — Rust colony expedition eligibility

Источник: замороженный `archive/rust-galaxy-067-reference`, `native/crates/sim_core/src/strategy/colony.rs`.

Colony body/source/ship eligibility; read-only admission; original shipyard idea deferred because no verified Rust shipyard constructor.

Статус: **CODE_UNVERIFIED**. Godot Runtime не запускался. Это самостоятельный GDScript-компонент, не часть живого TickRunner. Сохранение/восстановление только in-memory там, где явно реализовано; финансовые операции и складские списания должны выполняться авторитетными реестрами, а не этими моделями.

Интеграция откладывается до завершения компонентного переноса. Не объявлять функциональный паритет. Проверка: чтение точного Rust-источника и проверка отсутствия перезаписи существующих файлов; runtime не подтверждён.

# N78 — Rust strategic memory and hysteresis

Источник: замороженный `archive/rust-galaxy-067-reference`, `native/crates/sim_core/src/strategy/director.rs`.

Retain/switch policy with two decision-cycle confirmations and prepaid-plan retention; no order creation.

Статус: **CODE_UNVERIFIED**. Godot Runtime не запускался. Это самостоятельный GDScript-компонент, не часть живого TickRunner. Сохранение/восстановление только in-memory там, где явно реализовано; финансовые операции и складские списания должны выполняться авторитетными реестрами, а не этими моделями.

Интеграция откладывается до завершения компонентного переноса. Не объявлять функциональный паритет. Проверка: чтение точного Rust-источника и проверка отсутствия перезаписи существующих файлов; runtime не подтверждён.

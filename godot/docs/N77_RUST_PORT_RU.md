# N77 — Rust construction site durable material/labor state

Источник: замороженный `archive/rust-galaxy-067-reference`, `native/crates/sim_core/src/agents/construction.rs`.

Native site component; material delivery and paid labor require externally committed receipts; no facility spawning.

Статус: **CODE_UNVERIFIED**. Godot Runtime не запускался. Это самостоятельный GDScript-компонент, не часть живого TickRunner. Сохранение/восстановление только in-memory там, где явно реализовано; финансовые операции и складские списания должны выполняться авторитетными реестрами, а не этими моделями.

Интеграция откладывается до завершения компонентного переноса. Не объявлять функциональный паритет. Проверка: чтение точного Rust-источника и проверка отсутствия перезаписи существующих файлов; runtime не подтверждён.

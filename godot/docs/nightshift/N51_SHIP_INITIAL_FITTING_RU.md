# N51 — Rust-native стартовые слоты и модули кораблей

**CODE_UNVERIFIED.** Код и headless-тест написаны, Godot 4.7 в среде разработчика отсутствует. Зависимость: N46 / PR #136, отдельный независимый PR; N39 production, стабильная P1 и main не менялись.

## Rust-источники

- `native/crates/sim_core/src/modules/mod.rs`: 5 слотов (Engine, CargoBay, Sensors, Reactor, Comms), 15 модулей уровней T1–T3 с точными мультипликаторами, расходом/бюджетом мощности, бонусом коммс и радиусом сенсоров.
- `native/crates/sim_core/src/agents/ship/components.rs`: `ShipFitting::new_for_size`: Huge/Massive всегда T2 Sensors, Large выбирает T2 по чётности FNV-1a хеша **Rust ship-id**, а меньшие классы имеют T1. Слоты остальных систем — T1.
- `native/crates/sim_db/src/spawner.rs`: Rust ship-id строится из имени `ship-{name.to_lowercase().replace(' ', '-').remove_non_alnum_except_dash}`. Это отличается от временного N4 ключа `@system-id/index`. Парциальный `fitting={"comms":"comms_t2"}` не должен сбрасывать размерный сенсорный базис.
- `native/crates/sim_core/src/simulation/config.rs`: size speed multiplier уже присутствует в Godot `ship_catalog.gd`.

## Что реализовано

- `scripts/sim/ships/native_initial_fitting.gd`: все 15 slug/effects Rust; точные стартовые слоты каждого из 24 кораблей и снимок `DerivedStats`, power budget, радиус сенсоров, `comms_bonus`.
- Нормализация Rust id выполняется **по native имени**, не по N4 ordinal. Для ветки Large сенсоров считается точно FNV-1a `u64 % 2`: множитель нечётный, поэтому parity обновляется XOR младших бит UTF-8 байтов. Не зависит от 64-битных переполнений GDScript.
- Сохранённые/неизвестные fitting не принимаются за чистый новый seed. Неизвестные модули, неправильный слот, не применённые базовой моделью эффекты cargo/engine **отвергаются**, чтобы не обещать ускорение, которое действительный N14 ещё не применяет.
- `tests/n51_native_initial_fitting_check.gd`: 24 записей, T2 коммс с +0.05; 3 Huge hauler имеют сенсоры T2, 3 Large tanker по исходному Rust ID получают T1, остальные T1; power 5 либо 6 при cap 10; 0 вымышленных cargo/speed бонусов, отказы и детерминизм.

## Интеграция

Это **read-only projection стартовых оборудований**, а не реально установленная/действующая ship fitting система. Рефит по улучшениям T2–T3 и произвольные fitting modules требуют переноса формул в авторитетные ShipState/Transit/Cargo и единого save. Не применять изолированный `native_initial_fitting.gd` как источник денежной операции. Нет пользовательского тестирования отдельно от общей сборки.

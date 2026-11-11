# Living Sector — FIX2 после Windows тестов BCDEF

Источник: `LS-AI-Blocks-BCDEF-FIX1-SOURCES.zip` и логи пользователя `check(2).log`, `planning(1).log`, `RESULT(4).txt`.

- `cargo check -p sim_core -p sim_server -p sim_db`: PASS на Windows (только два предупреждения).
- `cargo test --locked -p sim_core strategy::planning`: 49/50 PASS; старый тест `no_facility_owned_market_does_not_invent_production` упал, потому что каталог стал принимать станционный рынок + отдельный завод.
- FIX2: целевой рынок обязан принадлежать существующему объекту собственной фракции **на той же локации**, независимо от того, совпадает ли владелец рынка с заводом. Это соответствует `PlanningSnapshot::capture`.
- Два теста: несущестующий владелец и владелец в другой локации блокируются. Сохранён положительный тест `native_station_market_uses_colocated_refinery_not_market_owner`.
- 10 доступных Python-тестов PASS. Rust в среде модели отсутствует; FIX2 ещё НЕ проверен компилятором.

Проверка на Windows: распаковать новый архив, запустить `VERIFY-AI-BLOCK-BCDEF.cmd`, прислать `AI-BLOCK-BCDEF-RESULTS.zip`. Проверка впервые сможет перейти к сборке сервера/короткому runtime только после всех unit-тестов.

Никаких изменений экономического баланса, штатных целей и поведения обычного режима.

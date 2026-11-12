# N52 — начальные деньги кораблей и единый денежный реестр

**CODE_UNVERIFIED.** Ветка от N46 / PR #136, без изменения N39 production/сохранённой P1/main/stable.

## Frozen Rust источники

- `native/crates/sim_db/src/seeder.rs`: fresh ship `credits = ship.credits` либо Rust default 5000, INSERT `ships.credits` в DB. Все 24 frozen world JSON имеют `credits=40000`, итого 960000.
- `native/crates/sim_db/src/spawner.rs`: реальный runtime `ShipEconomy.credits` восстанавливается из сохранённой БД без повторного стартового начисления.
- Godot N11 `scripts/sim/economy/credit_ledger.gd` — единственный каталог балансов и атомарных транзакций; `import_accounts` применим только к **первоначальным** аккаунтам ещё не запущенной игры.

## Код N52

- `scripts/sim/ships/native_ship_funding.gd` заново подтверждает все исходные ship credits через N46 `build_new_game(seed)`, маркирует только источник, формирует `ship:<@system-id/index>` балансы и проверяет сумму/overflow.
- `admit_into_empty_world_ledger(ledger, seed, other_authoritative_accounts)` **не создаёт второй Ledger**. Принимает явные реальные балансы фракций/станций/популяций из ещё не подключённых источников и выполняет **один** `N11.import_accounts` всей совокупности. Повторный вызов, существующий баланс/receipt, пустые источники других доменов, дубли `ship:` и невалидные суммы отвергаются.
- Это **программная входная граница**, не живое включение денег в P1: у N39 другого владельца свои station/facility кошельки, их нельзя создавать из предположений. N52 сам не вызывает `admit_into_empty_world_ledger` при запуске P1.
- N4 ключи пока являются временными Godot identity, не сохранёнными Rust database IDs. Единый World+Fleet save и схема постоянных ID ещё нужны.

## Регрессия

`tests/n52_initial_ship_funding_check.gd`: 24 ship balances = 960000, реальные тестовые дополнительные средства 500+100 заданы **явно как фикстуры**; единственный ledger total=960600; повторная инициализация/коллизия/отрицательные деньги fail-closed; последующая транзакция между двумя ship-account сохраняет сумму и idempotence после ledger restore.

Headless тест не выполнен: Godot 4.7 отсутствует в этой среде. Пользователю не нужны индивидуальные ZIP/запуски; этот блок ждёт общую интеграционную сборку.

# Living Sector — Чат №3 / В3: единый N38–N39–N9 checkpoint coherence

Дата: 14.11.2026 · PR #249 · ветка `integration/godot-phase2-unified-20261113`

## Проверенная причина для работы

Система N38 записывает `.pending` и затем проверяет SHA-256, а предыдущий блок чата №3 уже внедрил полное сравнение JSON с исходным N39-снимком. Но до записи не было отдельного fail-closed контроля, что сам **исходный** N39 World соответствует **единственному** реестру N9, а квитанции и очередь событий не живут в будущем относительно общего тика. Согласованное сериализованное искажение SHA256 не выявляет. Это безопасность checkpoint/архитектуры, НЕ новая механика экономики.

Авторитетные существующие источники: `n39_native_world_schema.gd::accounts`, `n39_native_world_production.gd::snapshot/restore`, `credit_ledger.gd::snapshot`, `tick_runner.gd::NATIVE_PHASE_ORDER`, `save_state.gd::save_runner`.

## Сделано в общей ветке

1. `5365002`: `godot/scripts/sim/phase2/unified_native_checkpoint_coherence.gd`. Pure read-only аудит из исходного checkpoint (без клонирования/изменения World). N39 world + N9 `balances` должны иметь *ровно* одни и те же счета и значения. Источники счетов: facilities credits, populations wealth, ships credits, faction treasuries, escrow balances, in-flight passenger manifests wealth. Проверяются типы, идентификаторы и отсутствие лишних кошельков. Нет попытки «исправлять» расхождения новой эмиссией.
2. История N9: для каждой квитанции id/kind/legs, целочисленный `receipt.tick <= checkpoint.tick`, корректные account/delta. **Не** требуем нулевую сумму квитанции: source N149 ship crew wages и N152 despawn — законные односторонние списания. Удалённый ship/facility account не восстанавливаем по архивному receipt.
3. Проверяется один tick `N39.tick == N1.tick`, корректность pending event due after committed tick, source-правильная фазовая граница. `2051ef4` заменяет локально фиксированное число фаз ссылкой на реальный `TickRunner.NATIVE_PHASE_ORDER`.
4. `6cbcf08`: `godot/scripts/sim/save_state.gd` вызывает этот аудит **до** сериализации и создания/замены `.pending`. Невалидный исходный checkpoint возвращает `ERR_INVALID_DATA`, предыдущие `.json`/`.bak` остаются нетронутыми. Уже существующий полный JSON fidelity gate работает отдельно после записи `.pending`.
5. `e7feeb7`: `godot/tests/p2_native_checkpoint_coherence_check.gd` — отложенный набор проверок: 6 типов счетов включая пассажирские, receipt N9 как history, легальное одностороннее списание N149, фантомный кошелёк, ложная казна, квитанция из будущего, повреждённый id, прошлый pending event, mismatch tick, сохранение исправного файла при отказе. **Не запускалось**.

## Границы и честный статус

**SOURCE_WIRED / CODE_UNVERIFIED.** Статически проверены балансы скобок, NUL, конечные переводы строк, SHA повторно считываемых файлов. Godot, headless, F5, Windows и GitHub Actions **не запускались**.

Не менялись `n39_native_world_production.gd`, `n39_native_world_schema.gd`, `n158_production_runtime.gd`, N9 Ledger, N104 Board, N84 Ship AI или балансы. При проверке Chat1 N83 free-trade lease уже RELEASED, но Chat2 B2 physical Metals lease продолжал быть IN_PROGRESS и владел N39/N158/Schema. Любое связывание В2 crisis event delivery требует дождаться завершения этих общих правок.

## Продолжение

1. На «Продолжай» проверить свежие HEAD + leases. Если Chat2 B2 отпустил N39/N158 — **закончить В2**: единый N39 commit для facility starving_notified после markets на фазе crisis, event transition через существующий N1/N158 path, N38 сохранение. Без дополнительных тиков/кошельков.
2. Иначе закончить В3: аудит единственного timeline и точек восстановления/производительности N38 для длинной истории N9, не трогая занятые файлы.
3. После завершения всей интеграции выполнить отложенный регрессионный `p2_native_checkpoint_coherence_check.gd` вместе с `p2_native_save_roundtrip_guard_check.gd` и полным runtime; записать фактические результаты, не выдавать написанные тесты за прошедшие.

Схема оригинала Rust остаётся эталоном.

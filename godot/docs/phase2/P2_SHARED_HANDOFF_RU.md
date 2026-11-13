# Living Sector / P2 — единый handoff для пяти автоматических смен

**Решение по ИИ — N80/N81/N84/N146 (13.11.2026):** в общей ветке теперь подключён **истинный архитектурный проход**: source N153 selects eligible offer → N80 scores goal → N81 GOAP makes plan → Rust N84 BT stores one-step-per-tick execution cursor → N146 `AcceptContract` / `BeginTransit` → единственные N104/N9 и N14/N39 Apply. Старый прямой цикл `contract → ship departure` удалён. Неподключённые paid N21/N97/N15 actions ожидают реального Apply, а не завершаются фиктивно. **Godot runtime НЕ проверен**. Следующий приоритет: N21/N97/N15 paid pickup/delivery+settlement и регрессионные тесты. Внимание: personality пока source `for_class` fallback, НЕ точный RNG Rust. [Подробный handoff](handoffs/20261113-interactive-n80-n81-n84-n146-real-pipeline.md).

**13.11.2026 23:28 МСК / N153:** исходная N153 selector policy подключена к настоящим опубликованным N104 контрактам; N39 атомарно принимает контракт и резервирует Rust comms_t2(+5%) в N9; N158 в фазе factions назначает автономного корабля, N14 ships фаза ведёт его по реальному графу к источнику. Старые ручные кнопки скрыты. **Не выполнено Godot**, **не сделано N97 paid pickup/physical cargo/settlement**. Следующий главный блок — N97/N21/N15 source pickup и дальнейшее N104 выполнение; [подробный handoff](handoffs/20261113-2328-interactive-n153-autonomy-acceptance.md).

**Новый действующий P2-этап (13.11.2026, 22:34 МСК):** N135 потребность → N104 реальный оплаченный контракт с escrow теперь проходит единый N39 World/N9 Ledger Apply во время N150 рыночной фазы. Исходники в общей ветке и read-only данные у наблюдателя. Тест `p2_live_funded_contract_check.gd` подготовлен, **НЕ выполнен в Godot**. Следующий приоритет — N153 автономное принятие и исполнение опубликованных контрактов, без ручных кнопок. Подробности: [20261113-2234-interactive-n135-n104-canonical-post.md](handoffs/20261113-2234-interactive-n135-n104-canonical-post.md).

**ВАЖНОЕ ОБНОВЛЕНИЕ ПРИОРИТЕТОВ 13.11.2026:** игрок просит **только автономный наблюдаемый сектор**, без индивидуального микроменеджмента. Все старые ручные N14/N21/N15 кнопки теперь DEBUG, скрыты по умолчанию; исходники оставить. До новых UI/мелких патчей требуется **сквозной AI execution**: N135 order/ContractBoard → N153 ship behavior + N80/N81/N84 → N97/N104 real cargo + funds, затем N134/N100 Head и станционные администраторы. Одна World/Ledger/Apply/save, без фиктивных рейсов. Точный план — [AUTONOMY_FIRST_RU.md](AUTONOMY_FIRST_RU.md). Каждая смена должна прочитать его и брать самый ранний свободный существенный участок; старые приоритеты ручных приказов ниже неактуальны.

**Прочитать перед работой:** `P2_INTEGRATION_EXECUTION_PLAN_RU.md` (истина о гейтах), `P2_LOCAL_WINDOWS_TEST_RU.md` (путь тестирования пользователя), `UNIFIED_RUNTIME_STATUS_RU.md` (история), `UNIFIED_IMPORT_CONFLICTS.json` (ручные конфликты).

**Последний достоверный Windows artifact:** [#43403286156](https://github.com/Mefits/Living-Sector/actions/runs/43403286156). Он включает замороженную Galaxy data, пользователь уже показал рабочий runtime с восемью системами, трёхфракционной картой и экономическими тиками. Это **не** новейшая версия исходников.

**Текущий новый UI в исходниках после artifact:** `godot/scripts/star_system_view.gd`, двойной клик по карте сектора, body inspector `godot/scripts/main.gd`, real-tick orbit redraw; добавлено в PR #249, локальный Godot run ещё не выполнен (`CODE_UNVERIFIED`). Не считать Windows build #43403286156 проверкой нового UI.

**Экономическая вертикаль действительно активна:** N39 paid production, N151 платное Food/Water потребление и удовлетворённость, N150 market pricing/history, один N9 ledger и SaveState. **Неактивны:** migration/colonization, facility condition/repairs, физический флот, товарные контракты, строительство, исследования, глава/администраторы/Hybrid и полный ECS persistence.

## Как оставлять передачу между сменами

Рекомендуется отдельный уникальный файл `godot/docs/phase2/handoffs/YYYYMMDD-HHMM-<agent>.md`, чтобы пять смен не писали в один и тот же файл параллельно. В файле максимум 15–25 содержательных строк: входной HEAD, точные коммиты, активный гейт, что реально теперь изменяется на тиках, какие файлы забраны/освобождены, выполненные **местные** проверки (или честно `CODE_UNVERIFIED`), блокеры и следующий самый ценный свободный участок. Handoff без кода не считается выполненной сменой.

Для claims использовать отдельный `godot/docs/phase2/leases/<unique>.json`, в начале IN_PROGRESS и в конце RELEASED; проверять время/коммиты другого исполнителя перед захватом старой задачи. Не присваивать себе одновременно `main.gd`, `n158_production_runtime.gd`, `SaveState`, `World` и общий CI без реальной необходимости. При независимой части — свой lease, ревизия актуальной ветки, аккуратный коммит без force-push. Изменения центрального runner согласовывать в одном месте и брать только одному владельцу.

## Статусы проверки (не врать)

- `SOURCE_PRESENT`: файл портирован, но никто не вызывал его на живом тике.
- `WIRED_CODE_UNVERIFIED`: код подключён к одной фазе, но Godot не запускался.
- `LOCAL_GODOT_PASS`: есть фактический лог локального Godot на конкретном SHA.
- `CI_GODOT_PASS`: проверено GitHub Actions на **том же** SHA.
- `USER_WINDOWS_PASS`: пользователь подтвердил видимое работающее поведение на Windows.
- `PLAYTEST_BUG`: есть воспроизведение, файлы/логи и точный ожидаемый результат.

**Actions budget:** 0 на мелкие правки. Новый smoke+Windows export только по единственному `CI_RELEASE_OWNER` lease после завершённого целого гейта или явного запроса пользователя; все остальные смены проверяют известный run и не дублируют. Ни один переход по source-only статусу не оправдывает cloud run.

## Начальный свободный участок после создания этого плана

Первым локально проверить новый system/body экран через Godot 4.7.2 (или подготовить корректный F5 запуск, если у смены есть локальный Godot); затем расширять живую экономическую вертикаль и переходить к единому Fleet. Не блокировать весь процесс на GUI, если нет доступа к Godot: полезный независимый engine-адаптер можно делать параллельно.


## Gate 2 — N46/N14 canonical ships source-wired, NOT runtime-verified

- 13.11.2026 interactive integration wrote a source-level vertical: **24 original N46 source ships** under the same `N39 world.ships` and `ship_next_token`, source ship Credits in the existing N9 ledger, **N14 real directed-route ship transit** in the one N158 `ships` stage, native moving orbital coordinates, manual `request_ship_departure()`, ship in-flight/fuel observer, save/reload integer normalization. No second TickRunner/Ledger. See full handoff `handoffs/20261113-p2-canonical-n46-n14-fleet-interactive.md` and test `godot/tests/p2_unified_ship_phase_check.gd`.
- **WIRED_CODE_UNVERIFIED**: Godot 4.7.2 not available inside this chat; NOT CI_VERIFIED or USER_WINDOWS_PASS. Existing Windows ZIP #43403286156 DOES NOT contain this change. Do not infer from source that fleet is working or autonomous. Only *manual* N14 route travel is wired; N153 autonomous goals, N21 docking, N15 cargo and N104 contracts remain.
- Before expanding the touched central `n158_production_runtime.gd`, `n39_native_world_production.gd`, `n39_native_world_schema.gd`, **first run locally** Godot parser and `p2_unified_ship_phase_check.gd`, previous `p2_n158_live_production_check.gd`, and `p2_n130_service_repair_check.gd`; fix real errors locally. **NO GITHUB ACTIONS for this checkpoint alone.** Lease was scoped to these files and is RELEASED; check latest commit/claims before next edits.
- Current new-game phase report: `bodies, ships, facilities, populations, markets`; older P2 saves **without ships** continue to load without refilling the entire 24-ship fleet. Do not invent migration data.

# Living Sector P2 — чат №3 · В3: восстановление N38 и защита резервной копии

Дата: 14 ноября 2026 · [PR #249](https://github.com/Mefits/Living-Sector/pull/249) · общая ветка `integration/godot-phase2-unified-20261113`.

## Обнаруженный дефект

`save_state.gd::save_runner` раньше считал старый primary «допустимым backup» просто по успешному N38 SHA-256 envelope. Но даже корректно захешированный payload может иметь повреждённый единый N39 World/N9 Ledger, а также нересторимые нативные часы/события, вследствие чего при следующем сохранении он мог вытеснить предыдущий `.bak`.

`load_runner` при успешной загрузке `.pending` повторно смотрел только на SHA старого primary. Поэтому **SHA-валидный, но отвергнутый настоящим `Runner.restore_checkpoint` primary** блокировал продвижение уже загруженного pending. После рестарта приходилось снова повторять восстановление.

## Изменения (SOURCE_WIRED)

- `9803419`: расширен `unified_native_checkpoint_coherence.gd`: `validate_serialized_candidate` делает *копию* данных и точно переводит JSON float→int только для известных полей N38/N39/N9 (tick, все физические кошельки, escrow, пассажиры, N9 receipt legs/timestamps, pending event due/phase), не изменяет оригинальный checkpoint, после чего использует уже существующий `validate()`. Непредставимые/дробные i64 отвергаются.
- `7a4c7bb`: `save_state.gd` требует семантически согласованный старый primary перед тем, как заменить им предыдущую резервную копию. Невалидный primary удаляется, `.bak` сохраняется.
- `e46d091`: старая копия также проходит **настоящие существующие парсеры** N1 `clock.restore`, `calendar.restore`, `cadence.restore`, `event_queue.restore` (временные read-only объекты, никакой второй симуляции).
- `7a4c7bb`: успешное `load_runner(...)` из `.pending` теперь продвигает его в primary даже если предыдущий primary SHA-валиден, потому что реальный Runner уже отверг и primary, и backup; `.bak` не трогается.
- `b8102e6`, `bf13d0a`, `879a53a`: новый отложенный регрессионный `godot/tests/p2_native_save_recovery_check.gd`. Матрица: N39/N9-SHA-valid corrupted primary + healthy backup; оригинальный N1 clock с недопустимым TPS; receipts из будущего; успешная pending promotion после двух runtime restore failures; приоритет исправного primary/backup над pending; все кандидаты отвергнуты => не изменять baseline и файлы; сохранение сохранённой `.bak`. **Тест не запускался.**

## Строгие границы

**SOURCE_WIRED / CODE_UNVERIFIED**, только повторный GitHub source readback, balanced `[]{}()`, проверка парных кавычек, NUL, EOL, табов. Godot parser, headless, F5, Windows, GitHub Actions НЕ запускались. Пользователь отдельно просил не проводить промежуточные тесты до полного переноса Rust.

Этот guard — **не доказательство полной runtime-restorability**: для окончательного решения требуется `Runner.restore_checkpoint` с настоящим seed/World; поэтому после подготовки к load сохраняется существующий порядок `primary → .bak → .pending` и transactional rollback. Не заявлять, что каждый прошедший preflight primary гарантированно валиден.

В рамках данного блока НЕ редактировались `n39_native_world_production.gd`, `n39_native_world_schema.gd`, `n158_production_runtime.gd`, N9, N104, N84, игра/баланс. Chat1 параллельно занят N108 GateJump на общих N39/N158. Chat2 B2 выпущен, далее Б3. Никакого изменения реальных игровых механик.

## Продолжение

- Следующее «Продолжай» — снова проверить свежий HEAD и leases. Если N39/N158 свободны, добить В2 `markets→crisis→apply2`: persisted `starving_notified` + реальные transition events через единственный runtime. Если они заняты, продолжить В3 source audit recovery и архитектурных миграций без параллельной редакции.
- Финальное общее Godot принятие: запустить `p2_native_save_recovery_check.gd`, `p2_native_checkpoint_coherence_check.gd`, `p2_native_save_roundtrip_guard_check.gd`; проверить точность N9 и аварийное прерывание save/pending; записать реальные PASS/FAIL.

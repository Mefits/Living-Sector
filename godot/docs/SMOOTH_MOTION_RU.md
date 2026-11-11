# Плавность кораблей без ложных игровых перемещений

**Проблема, которую следует искать:** кадр дёргается (*jitter / stutter*), хотя игровые тики идут стабильно. Не путать с **jiggle** (подпрыгивание/пружинный вторичный эффект): Living Sector прежде всего нужен **physics/render interpolation**.

## Два разных времени

- **Симуляционный тик:** принимает решения, списывает топливо, перемещает груз, отмечает фактическое прибытие, меняет склад/контракт. Даже при ×16 всегда выполняет игровой порядок фаз и транзакций.
- **Кадр экрана:** показывает текущее состояние, может рисоваться 60/120 FPS при менее частом обновлении игрового состояния.
- **Решение:** сохраняем **предыдущую и текущую позицию**, между ними рисуем переход с коэффициентом от 0 до 1. Интерполяция **не меняет координаты в SimWorld** и не оформляет доставку.

## Если корабль — обычный Node2D и обновляется в physics tick

Встроенная [Godot physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html): Project Settings → Physics → Common → Physics Interpolation. Положение/поворот обновляются в _physics_process, рендер интерполируется между физическими тиками. После телепорта/перезагрузки/смены системы использовать reset_physics_interpolation(), чтобы не протягивать след через всю карту.

**Важное ограничение:** это автоматическое сглаживание физики Godot, **не** автоматическая интерполяция произвольной экономической модели, пересчитываемой несколько раз за physics tick.

## Если у нас тысячи компактных кораблей — целевой путь

Модель хранит ship.position, route, native progress, реальные tick snapshots. Отображение отдельно хранит last_rendered / previous / current и отображает сглаженную координату, например:

    visual_position = previous_position.lerp(current_position, alpha)

Коэффициент alpha берётся из времени между **действительными снимками**, а не из случайного Tween; Engine.get_physics_interpolation_fraction() применим, если эти снимки обновляются синхронно с physics tick. При отдельном fixed-step scheduler потребуется свой строго ограниченный interpolation alpha на основании накопленного времени и timestamps.

При ×16 возможны несколько игровых шагов на один экранный кадр: не проигрывать по одной анимации на каждый шаг — это будет копиться и отставать. Renderer получает актуальный компактный снимок после пакета тиков, рисует между корректными временными точками; если произошёл jump/новая система/удаление корабля, **сбрасывает интерполяцию**, а не изображает ошибочный полёт.

Не подменять истинную позицию будущей предсказанной координатой без контроля. При изменении маршрута учитываем смену ID отрезка, докинг и фактические события.

## Что **не** поможет само по себе

- Tween, вручную применённый после каждого тика, может накопить «хвост» плавных перемещений и отстать от мира.
- Camera2D position smoothing сглаживает **камеру**, но не движение 1000 разных кораблей.
- Physics bodies и collision detection не нужны для стратегической симуляции орбит/торговых рейсов с явными путями.
- Path2D/PathFollow2D полезны для **отрисовки** траектории, но не должны решать, когда товар реально прибыл.
- Встроенная physics interpolation не волшебно исправит нестабильный FPS, тормозной UI, резкую подмену state или отсутствие snapshot timestamps.

## Порядок внедрения

1. P1: fixed-step tick и снапшоты позиций, независимые от рендера.
2. P3: один настоящий корабль с маршрутом/временем/топливом и оформлением прихода через симуляцию.
3. P7: presenter интерполирует корабли между подтверждёнными кадрами, camera smoothing отдельно.
4. Профиль: 100, 1000, 10000 кораблей. Сначала [CanvasItem custom drawing](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html), затем [MultiMeshInstance2D](https://docs.godotengine.org/en/stable/classes/class_multimeshinstance2d.html) по реальным узким местам, далее RenderingServer при необходимости.
5. Один короткий визуальный сценарий: 10 TPS модели, 60 FPS рендера, после этого ×16 и прыжок между системами; **без** нарушения фактических координат/контрактов. Тест запланирован, **не проведён**.

Полезные главы: [Godot: interpolation introduction](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html), [using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html), [2D vs 3D](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html), [Godot: performance using MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

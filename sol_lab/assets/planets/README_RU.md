# Планеты Sol и визуальные биомы

Это графика из двух пользовательских архивов, а не изменение симуляции.

- sol/planets и sol/map_icons: 9 отдельных изображений планет
  Солнечной системы и Луны (256x256 и 32x32).
- biomes/planets и biomes/map_icons: 12 типовых биомов,
  изображения 256x256 и миниатюры 32x32.

Для system-sol изображения назначаются по id тела: mercury, venus,
earth, luna (файл moon), mars, jupiter, saturn, uranus, neptune.

В остальных системах применяется поле visual_biome (если задано),
а иначе существующее поле biome. Доступные значения:
earthlike, marslike, gas_giant, ice_world, volcanic, barren,
ocean_world, desert_world, venuslike, ice_giant, titanlike,
tidally_locked. Соответствия старых названий: terrestrial -> earthlike,
ice -> ice_world, molten -> volcanic, lifeless -> barren,
desert -> desert_world.

Малые тела используют 32px-иконки, увеличенные — 256px спрайты.
Сатурну выделена дополнительная ширина для колец. Если изображения
нет, остаётся старая процедурная отрисовка. Кликабельные постройки,
орбиты, игровые размеры и склады не меняются.

В текущем sol_lab/data/sol.json отсутствуют Уран и Нептун:
изображения готовы, но новые игровые тела намеренно не создаются.
Для Каллисто отдельного рисунка в исходном Sol-наборе нет,
используется универсальный безжизненный мир.

Проверка:
godot --headless --path sol_lab -s res://tests/sol_planet_sprites_check.gd

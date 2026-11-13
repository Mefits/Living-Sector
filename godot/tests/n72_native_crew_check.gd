extends SceneTree
const Model = preload("res://scripts/sim/ships/native_crew_upkeep.gd")
func _initialize() -> void:
	var m = Model.new()
	var crew = {"size":2,"hunger":60.0,"fatigue":0.0,"morale":80.0,"health":100.0,"task":"piloting","wages_credits":0}
	var ship = {"crew":crew,"food":10,"food_per_meal":1,"meal_reduction":30.0,"credits":100,"docked":false,"in_transit":true}
	assert(m.import_ships({"ship":ship}))
	assert(m.step(5,1.0,1).ok)
	var s = m.snapshot()
	assert(s.ships.ship.food == 8 and s.ships.ship.crew.hunger < 60.0)
	assert(not m.step(5,1.0,1).ok)
	for tick in range(6,51):
		assert(m.step(tick,0.0,1).ok)
	s = m.snapshot()
	assert(s.ships.ship.credits == 90 and s.ships.ship.crew.wages_credits == 10)
	var copy = Model.new()
	assert(copy.restore(s))
	assert(not copy.step(50,1.0,1).ok)
	print("N72 PASS")
	quit()

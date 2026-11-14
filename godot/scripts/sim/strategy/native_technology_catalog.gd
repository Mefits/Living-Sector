extends RefCounted
## N82: immutable source-backed director.rs TECHNOLOGIES; not a paid research executor.
const TECHNOLOGIES: Array[Dictionary] = [
	{"id": "industrial_methods", "name": "Промышленная организация", "prerequisite": "", "work": 40, "field": "industry", "effect": "+1 партия за производственный цикл, с расходом сырья"},
	{"id": "orbital_habitats", "name": "Орбитальные поселения", "prerequisite": "", "work": 50, "field": "expansion", "effect": "Основание новых станций"},
	{"id": "deep_navigation", "name": "Межзвёздная навигация", "prerequisite": "orbital_habitats", "work": 70, "field": "expansion", "effect": "Колонизация за пределами стартовой системы"},
	{"id": "automation", "name": "Промышленная автоматизация", "prerequisite": "industrial_methods", "work": 90, "field": "industry", "effect": "Ещё +1 партия за производственный цикл, с расходом сырья"},
	{"id": "alloytech2", "name": "Металлургия сплавов T2", "prerequisite": "automation", "work": 110, "field": "industry", "effect": "Разрешение оплачиваемого производства сплавов"},
	{"id": "survey2", "name": "Геологическая разведка T2", "prerequisite": "deep_navigation", "work": 110, "field": "science", "effect": "Открытие месторождений редкой руды"},
	{"id": "drilltech2", "name": "Глубинная добыча T2", "prerequisite": "alloytech2", "work": 120, "field": "industry", "effect": "Добыча редкой руды после разведки"},
	{"id": "structuretech2", "name": "Модульное ядро T2", "prerequisite": "alloytech2", "work": 160, "field": "industry", "effect": "Разрешение проекта улучшения станции T2"},
	{"id": "survey3", "name": "Геологическая разведка T3", "prerequisite": "survey2", "work": 160, "field": "science", "effect": "Открытие кристаллической руды"},
	{"id": "drill3", "name": "Глубинная добыча T3", "prerequisite": "drilltech2", "work": 180, "field": "industry", "effect": "Добыча кристаллической руды после разведки"},
	{"id": "quantumtech3", "name": "Квантовое производство T3", "prerequisite": "structuretech2", "work": 220, "field": "science", "effect": "Разрешение производства квантовых ядер"},
	{"id": "structuretech3", "name": "Модульное ядро T3", "prerequisite": "quantumtech3", "work": 250, "field": "industry", "effect": "Разрешение проекта улучшения станции T3"}
]

static func all() -> Array[Dictionary]:
	return TECHNOLOGIES.duplicate(true)

static func find(id: String) -> Dictionary:
	for technology in TECHNOLOGIES:
		if technology.id == id:
			return technology.duplicate(true)
	return {}

static func has(completed: Array, id: String) -> bool:
	return completed.has(id)

static func production_bonus(completed: Array) -> int:
	return int(has(completed, "industrial_methods")) + int(has(completed, "automation"))

static func eligible(completed: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for technology in TECHNOLOGIES:
		if completed.has(technology.id):
			continue
		if not technology.prerequisite.is_empty() and not completed.has(technology.prerequisite):
			continue
		result.append(technology.duplicate(true))
	return result

static func choose(completed: Array, profile: Dictionary) -> Dictionary:
	# Rust director.rs observe: highest field weight, then lexicographically smallest ID.
	var best: Dictionary = {}
	var best_score := -INF
	for technology in eligible(completed):
		var field: String = technology.field
		var score: float = float(profile.get(field, 0.0))
		if not is_finite(score):
			continue
		if best.is_empty() or score > best_score or (score == best_score and technology.id < best.id):
			best = technology
			best_score = score
	return best

static func required_work(id: String) -> int:
	return int(find(id).get("work", 0))

static func can_complete(id: String, completed: Array, paid_work: int) -> bool:
	var technology := find(id)
	return not technology.is_empty() and paid_work >= int(technology.work) and paid_work >= 0 and not completed.has(id) and (technology.prerequisite.is_empty() or completed.has(technology.prerequisite))

static func next_for_target(target: String, completed: Array) -> Dictionary:
	# Walk a single prerequisite chain, never mint completion or paid work.
	var seen: Dictionary = {}
	var current := target
	while not current.is_empty():
		if seen.has(current):
			return {}
		seen[current] = true
		var tech := find(current)
		if tech.is_empty():
			return {}
		if not completed.has(current):
			var prerequisite: String = tech.prerequisite
			if prerequisite.is_empty() or completed.has(prerequisite):
				return tech
			current = prerequisite
		else:
			return {}
	return {}

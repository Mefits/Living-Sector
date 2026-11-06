// Pure, read-only adapter for GET /api/strategy v1.
// Never infer execution or progress from scores, proposed goals or HTTP freshness.
export const goalLabels = Object.freeze({
  sustain_population: "Снабжение населения",
  secure_fuel: "Обеспечение топливом",
  supply_industry: "Снабжение промышленности"
});
export const decisionLabels = Object.freeze({
  observing: "Наблюдение", idle: "Нет предложений",
  proposed: "Предложение", blocked: "Заблокировано",
  waiting: "Ожидание", commissioned: "Контракт создан"
});
export const reasonLabels = Object.freeze({
  awaiting_cycle: "Ожидание следующего анализа",
  no_chronic_shortage: "Не выявлено длительного дефицита",
  shadow_no_mutation: "Диагностический режим: деньги и контракты не меняются",
  no_accessible_stock: "Нет доступного запаса в подходящем источнике",
  insufficient_budget: "Недостаточно свободного бюджета",
  existing_contract: "Для потребности уже существует контракт",
  funded_native_contract: "Создан обеспеченный штатный контракт"
});
export const projectLabels = Object.freeze({
  posted: "Опубликован", accepted: "Принят",
  picked_up: "Груз забран", delivered: "Доставлен",
  paid: "Оплачен", expired: "Истёк"
});
export const commodityLabels = Object.freeze({
  ore:"Руда", ice:"Лёд", gas:"Газ", metals:"Металлы",
  fuel:"Топливо", polymers:"Полимеры", water:"Вода",
  components:"Компоненты", electronics:"Электроника",
  tools:"Инструменты", food:"Продовольствие",
  medical:"Медикаменты", luxury:"Предметы роскоши"
});
export function human(value, dictionary) {
  const code = String(value ?? "");
  return dictionary[code] || code || "—";
}
export function goalKey(goal) {
  if (!goal) return null;
  // A goal_id is a category, not a unique instance.
  return JSON.stringify([goal.goal_id, goal.commodity, goal.destination]);
}
export function parseSnapshot(input) {
  if (!input || input.schema_version !== 1 || !Array.isArray(input.factions) ||
      !Number.isSafeInteger(input.snapshot_tick) || input.snapshot_tick < 0 ||
      !["shadow","execute"].includes(input.mode)) {
    throw new Error("Неподдерживаемый формат /api/strategy (ожидается v1)");
  }
  const factions = input.factions.map(f => ({
    faction_id: String(f.faction_id ?? ""),
    observed_tick: Number.isSafeInteger(f.observed_tick) ? f.observed_tick : null,
    treasury: Number.isFinite(f.treasury) ? f.treasury : null,
    goals: Array.isArray(f.goals) ? f.goals : [],
    selected_goal: f.selected_goal ?? null,
    administrator: String(f.administrator ?? "—"),
    status: String(f.status ?? "—"),
    reason: String(f.reason ?? "—"),
    projects: Array.isArray(f.projects) ? f.projects : []
  })).filter(f=>f.faction_id);
  return {
    schema_version: 1,
    snapshot_tick: input.snapshot_tick,
    mode: input.mode,
    factions
  };
}
export function observedChanges(before, after) {
  // This is a local diff of observed snapshots, NOT an authoritative event log.
  if (!before || !after || after.snapshot_tick <= before.snapshot_tick) return [];
  const results = [];
  const previous = new Map(before.factions.map(f => [f.faction_id, f]));
  for (const now of after.factions) {
    const old = previous.get(now.faction_id);
    if (!old) continue;
    const add = message => results.push({
      faction_id: now.faction_id, tick: after.snapshot_tick, message
    });
    if (goalKey(old.selected_goal) !== goalKey(now.selected_goal)) {
      const target = now.selected_goal;
      add(target
        ? "Выбран приоритет: " + human(target.goal_id, goalLabels) +
          " · " + human(target.commodity, commodityLabels) +
          " → " + String(target.destination ?? "—")
        : "Выбранный приоритет больше не указан");
    }
    if (old.status !== now.status || old.reason !== now.reason) {
      add("Решение: " + human(now.status, decisionLabels) +
        " · " + human(now.reason, reasonLabels));
    }
    const oldProjects = new Map(old.projects.map(p => [p.contract_id, p]));
    for (const project of now.projects) {
      if (!project.contract_id) continue;
      const previousProject = oldProjects.get(project.contract_id);
      if (!previousProject) {
        add("Впервые наблюдаем проект " + project.contract_id +
          " · " + human(project.state, projectLabels));
      } else if (previousProject.state !== project.state) {
        add("Проект " + project.contract_id + ": " +
          human(previousProject.state, projectLabels) + " → " +
          human(project.state, projectLabels));
      }
    }
  }
  return results;
}
export function observationAge(snapshot, faction) {
  if (!snapshot || !faction || !Number.isSafeInteger(faction.observed_tick)) return null;
  return Math.max(0, snapshot.snapshot_tick - faction.observed_tick);
}

// Pure, read-only adapter for GET /api/strategy v1.
// Never infer execution or progress from scores, proposed goals or HTTP freshness.
export const goalLabels = Object.freeze({
  sustain_population: "Снабжение населения",
  secure_fuel: "Обеспечение топливом",
  supply_industry: "Снабжение промышленности",
  expand_production: "Расширение производства"
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
  funded_native_contract: "Создан обеспеченный штатный контракт",
  head_priority: "Ожидает решения главы: выбран другой администратор",
  ready: "Доступно для выбора",
  site_owned_by_other_faction: "Площадка принадлежит другой фракции",
  no_producer: "Не найден тип производителя для ресурса",
  producer_already_present: "Такой производитель здесь уже существует",
  invalid_site_location: "Невозможно разместить объект в этой точке",
  no_local_resource: "На планете отсутствует необходимый добываемый ресурс",
  awaiting_materialization: "Ожидается завершение строительства"
});
export const administratorLabels = Object.freeze({
  logistics: "Логистика", construction: "Строительство"
});
export const headReasonLabels = Object.freeze({
  urgent_supply: "Срочное снабжение продовольствием, водой или топливом",
  finish_existing_construction: "Продолжение существующей стройки",
  expand_production: "Расширение производства",
  supply_industry: "Снабжение промышленности",
  no_feasible_proposal: "Нет выполнимых предложений",
  already_commissioned_this_tick: "Новый контракт уже создан в этом тике"
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
    projects: Array.isArray(f.projects) ? f.projects : [],
    assessments: Array.isArray(f.assessments) ? f.assessments : [],
    construction: f.construction && typeof f.construction === "object" ? f.construction : null,
    head: f.head && typeof f.head === "object" ? f.head : null
  })).filter(f=>f.faction_id);
  return {
    schema_version: 1,
    snapshot_tick: input.snapshot_tick,
    mode: input.mode,
    factions
  };
}

export function assessmentForGoal(faction, goal) {
  const wanted = goalKey(goal);
  return (faction?.assessments ?? []).find(a => goalKey(a?.goal) === wanted) ?? null;
}
export function projectGroups(faction) {
  const projects = faction?.projects ?? [];
  return {
    logistics: projects.filter(project => project.administrator !== "construction"),
    construction: projects.filter(project => project.administrator === "construction")
  };
}
export function progressFraction(construction) {
  const required = construction?.progress_required;
  const delivered = construction?.progress_delivered;
  if (!Number.isFinite(required) || required <= 0 || !Number.isFinite(delivered)) return null;
  return Math.max(0, Math.min(1, delivered / required));
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
    const wasHead = old.head;
    const isHead = now.head;
    if (isHead && (!wasHead || (Number.isSafeInteger(isHead.observed_tick) &&
      isHead.observed_tick > (wasHead.observed_tick ?? -1)))) {
      const changed = !wasHead || wasHead.selected_administrator !== isHead.selected_administrator ||
        wasHead.reason !== isHead.reason;
      if (changed) {
        add("Глава: " + (isHead.selected_administrator
          ? human(isHead.selected_administrator, administratorLabels)
          : "Никто не выбран") + " · " + human(isHead.reason, headReasonLabels));
      }
    }
    const fromConstruction = old.construction;
    const toConstruction = now.construction;
    if (toConstruction) {
      if (fromConstruction && (fromConstruction.status !== toConstruction.status ||
          fromConstruction.reason !== toConstruction.reason)) {
        add("Строительство: " + human(toConstruction.status, decisionLabels) +
          " · " + human(toConstruction.reason, reasonLabels));
      }
      if (toConstruction.site_id && fromConstruction?.site_id === toConstruction.site_id &&
          Number.isFinite(toConstruction.progress_delivered) &&
          toConstruction.progress_delivered !== fromConstruction.progress_delivered) {
        add("Стройплощадка " + toConstruction.site_id + ": " +
          toConstruction.progress_delivered + " / " + toConstruction.progress_required);
      }
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

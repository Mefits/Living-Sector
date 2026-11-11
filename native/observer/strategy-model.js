// Pure, read-only adapter for GET /api/strategy v1.
// Never infer execution or progress from scores, proposed goals or HTTP freshness.
export const goalLabels = Object.freeze({
  sustain_population: "Снабжение населения",
  secure_fuel: "Обеспечение топливом",
  supply_industry: "Снабжение промышленности",
  expand_production: "Расширение производства",
  colony_life_support: "Снабжение колонии",
  colony_electronics_chain: "Промышленность колонии"
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
  awaiting_materialization: "Ожидается завершение строительства",
  positive_projected_relief: "Ожидается полезный эффект",
  unprofitable_source: "Поставка экономически невыгодна",
  no_construction_proposal: "Нет подходящего строительного проекта",
  reconsider_next_cycle: "Повторная оценка в следующем цикле"
});
export const administratorLabels = Object.freeze({
  logistics: "Логистика", construction: "Строительство"
});
export const headReasonLabels = Object.freeze({
  urgent_supply: "Срочное снабжение продовольствием, водой или топливом",
  finish_existing_construction: "Продолжение существующей стройки",
  expand_production: "Расширение производства",
  colony_life_support: "Снабжение колонии",
  colony_electronics_chain: "Промышленность колонии",
  supply_industry: "Снабжение промышленности",
  no_feasible_proposal: "Нет выполнимых предложений",
  already_commissioned_this_tick: "Новый контракт уже создан в этом тике",
  best_projected_relief: "Выбран вариант с наибольшим прогнозируемым эффектом",
  previous_goal_unavailable: "Прежняя цель больше недоступна — выбрана новая",
  viable_commitment_retained: "Прежний стратегический выбор остаётся полезным",
  outstanding_native_plan_retained: "Уже выполняемый нативный план сохраняет приоритет",
  urgent_life_support: "Кризис воды или еды — приоритет выживания",
  alternative_not_strong_enough: "Преимущество альтернативы недостаточно для смены стратегии",
  alternative_pending_confirmation: "Новая стратегия требует подтверждения в следующем цикле",
  sustained_higher_utility: "Преимущество новой стратегии подтвердилось два цикла подряд",
  survival_no_feasible_proposal: "Кризис снабжения: допустимое решение пока не найдено",
  no_feasible_strategic_choice: "Сейчас нет выполнимого стратегического варианта",
  colony_life_support_native_goal: "Поддержание реальных запасов воды и продовольствия колонии",
  colony_industrial_chain_native_goal: "Следующий этап: реальное производство электроники в колонии",
  colony_workforce_needed: "Нужно перевезти рабочих в колонию",
  colony_migration_approved: "Перевозка работников профинансирована"
});
export const optionLabels = Object.freeze({
  deliver: "Доставить", build: "Построить", wait: "Подождать"
});
export const optionStatusLabels = Object.freeze({
  ready: "Возможен", blocked: "Недоступен", waiting: "Ожидание"
});
export const optionReasonLabels = Object.freeze({
  positive_projected_relief: "Положительный прогноз",
  unprofitable_source: "Поставка экономически невыгодна",
  no_accessible_stock: "Нет доступного запаса",
  insufficient_budget: "Не хватает бюджета",
  producer_already_present: "Производитель уже существует",
  no_construction_proposal: "Стройка не предложена",
  reconsider_next_cycle: "Вернуться к выбору в следующем цикле"
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
    factions,
    stations: Array.isArray(input.stations) ? input.stations : [],
    colonies: Array.isArray(input.colonies) ? input.colonies : [],
    orders: Array.isArray(input.orders) ? input.orders : [],
    ai_execution: input.ai_execution && typeof input.ai_execution === "object" ? input.ai_execution : null,
    commanders: input.commanders && typeof input.commanders === "object" && !Array.isArray(input.commanders)
      ? input.commanders : {}
  };
}

// The server owns execution truth. This adapter NEVER changes a forecast into
// a native receipt. Absence of the optional field means "not observed".
export const nativeStepLabels = Object.freeze({
  planned: "Запланирован", prepared: "Подготовлен", submitted: "Заказ выдан",
  running: "Выполняется", succeeded: "Подтверждён", failed: "Ошибка",
  cancelled: "Отменён"
});
export function nativeGoalText(goal) {
  if (!goal || typeof goal !== "object") return "Цель не передана";
  const commodity = human(goal.commodity, commodityLabels);
  const location = String(goal.destination_id ?? "—");
  const amount = Number.isFinite(goal.target_units) ? ` ≥ ${goal.target_units}` : "";
  return `${commodity}${amount} · ${location}`;
}
export function nativeOutcomeVerified(outcome) {
  if (!outcome || outcome.final_status !== "completed") return false;
  const target = outcome.goal?.target_units;
  if (!Number.isSafeInteger(target) || target <= 0) return false;
  const steps = outcome.steps;
  if (!Array.isArray(steps) || steps.length === 0 ||
      !steps.every(record => record?.phase === "succeeded" &&
        typeof record.native_order_id === "string" && record.native_order_id.length > 0)) return false;
  if (outcome.reason === "native_receipts_and_goal_stock_confirmed") {
    return Number.isFinite(outcome.observed_goal_stock) && outcome.observed_goal_stock >= target;
  }
  if (outcome.reason === "native_recipe_receipts_and_goal_production_confirmed") {
    return Number.isSafeInteger(outcome.required_goal_production_units) &&
      outcome.required_goal_production_units > 0 &&
      outcome.required_goal_production_units <= target &&
      Number.isFinite(outcome.produced_goal_units) &&
      outcome.produced_goal_units + 0.0001 >= outcome.required_goal_production_units &&
      steps.some(record => record.native_order_id.startsWith("facility:") &&
        record.reason_code === "native_recipe_paid_and_output_counter_confirmed");
  }
  return false;
}
export function nativeExecutionForFaction(snapshot, factionId) {
  const state = snapshot?.ai_execution;
  if (!state || typeof state !== "object") return null;
  const active = state.active && typeof state.active === "object"
    ? state.active[factionId] ?? null : null;
  const deferred = state.deferred_goals && typeof state.deferred_goals === "object"
    ? state.deferred_goals[factionId] ?? null : null;
  const history = Array.isArray(state.history)
    ? state.history.filter(x => x?.faction_id === factionId).slice(-8).reverse() : [];
  const ledger = active?.ledger;
  const steps = Array.isArray(ledger?.steps) ? ledger.steps : [];
  const completed = steps.filter(x => x?.phase === "succeeded").length;
  return {
    active, deferred, history, steps, completed,
    blockedUntil: Number.isSafeInteger(state.blocked_until?.[factionId])
      ? state.blocked_until[factionId] : null,
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

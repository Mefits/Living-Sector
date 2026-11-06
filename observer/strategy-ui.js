// Independent, read-only strategy drawer. No writes to the simulation API.
import {
  parseSnapshot, observedChanges, observationAge, goalKey,
  human, goalLabels, commodityLabels, decisionLabels, reasonLabels, projectLabels,
  administratorLabels, headReasonLabels, assessmentForGoal, projectGroups, progressFraction,
  optionLabels, optionStatusLabels, optionReasonLabels
} from "/observer/strategy-model.js";

const format = new Intl.NumberFormat("ru-RU", {maximumFractionDigits: 1});
const text = value => value === null || value === undefined ? "—" : String(value);
const formatNumber = value => Number.isFinite(value) ? format.format(value) : "—";
const node = (tag, content, className) => {
  const element = document.createElement(tag);
  if (content !== undefined) element.textContent = text(content);
  if (className) element.className = className;
  return element;
};
const find = id => document.getElementById(id);

let elements;
let getFactions = () => [];
let snapshot = null;
let selectedFaction = null;
let changes = [];
let pending = false;
let requestError = null;

function strategyFactionName(id) {
  return getFactions().find(f => f.id === id)?.name || id;
}
function addField(parent, label, value) {
  const row = node("div", undefined, "strategy-field");
  row.append(node("span", label, "strategy-field-label"), node("span", value, "strategy-field-value"));
  parent.appendChild(row);
}
function addNote(parent, message) {
  parent.append(node("p", message, "strategy-note"));
}
function showEmpty(container, message) {
  container.replaceChildren(node("p", message, "strategy-empty"));
}
function setOpen(open) {
  if (!elements) return;
  elements.drawer.hidden = !open;
  elements.backdrop.hidden = !open;
  elements.toggle.setAttribute("aria-expanded", String(open));
  document.body.classList.toggle("strategy-open", open);
  if (open) {
    elements.close.focus();
    poll();
  } else {
    elements.toggle.focus();
  }
}
export function openStrategyForFaction(id = null) {
  if (!elements) return;
  if (id) selectedFaction = String(id);
  setOpen(true);
  render();
}

function fillFactionSelect() {
  const select = elements.faction;
  const current = selectedFaction;
  select.replaceChildren();
  if (!snapshot?.factions.length) {
    select.appendChild(new Option("Нет сведений о фракциях", ""));
    select.disabled = true;
    return null;
  }
  select.disabled = false;
  const sorted = [...snapshot.factions].sort((a, b) =>
    strategyFactionName(a.faction_id).localeCompare(strategyFactionName(b.faction_id), "ru"));
  for (const faction of sorted) {
    select.appendChild(new Option(strategyFactionName(faction.faction_id), faction.faction_id));
  }
  const present = sorted.some(f => f.faction_id === current);
  selectedFaction = present ? current : sorted[0].faction_id;
  select.value = selectedFaction;
  return snapshot.factions.find(f => f.faction_id === selectedFaction);
}
function strategyRenderHead(faction) {
  const target = elements.head;
  target.replaceChildren();
  const head = faction.head;
  if (!head) return showEmpty(target,
    "Этот сервер ещё не передаёт решения главы (поле head доступно с S4). " +
    "Показанные ниже логистические решения не являются общим выбором главы.");
  const card = node("article", undefined, "strategy-summary-card strategy-head-card");
  const chosen = head.selected_administrator
    ? human(head.selected_administrator, administratorLabels) : "Нет выбранного администратора";
  card.append(node("div", "РЕШЕНИЕ ГЛАВЫ · ТИК " + formatNumber(head.observed_tick),
    "strategy-eyebrow"));
  card.append(node("h3", chosen, "strategy-faction-name"));
  card.append(node("p", human(head.reason, headReasonLabels), "strategy-decision-reason"));
  addField(card, "Казна при выборе", formatNumber(head.treasury_before) + " CR");
  addField(card, "Доступно для выбора", formatNumber(head.spending_limit) + " CR");
  addField(card, "План платежа", formatNumber(head.planned_spend) + " CR");
  addField(card, "Фактически зарезервировано", formatNumber(head.committed_spend) + " CR");
  const age = observationAge(snapshot, head);
  if (age !== null && age > 0) addNote(card,
    "Данные относятся к последнему решению главы, а не к текущему балансу.");
  target.append(card);
  // S7 options use forecast data; never equate covered_units with the native contract quantity.
  const options = Array.isArray(head.alternatives) ? head.alternatives : null;
  if (options) {
    if (head.problem) {
      const problem = head.problem;
      const caption = node("div", "ПРОБЛЕМА · " +
        human(problem.commodity, commodityLabels) + " → " + text(problem.destination),
        "strategy-problem-title");
      target.append(caption);
      addNote(target, "Дефицит: " + formatNumber(problem.shortage_ticks) +
        " тик. · Горизонт прогноза: " + formatNumber(head.horizon_ticks) + " тик.");
    }
    target.append(node("h4", "ВАРИАНТЫ ГЛАВЫ · S7", "strategy-subheading"));
    for (const option of options) {
      const selected = option.action === head.selected_option;
      const item = node("article", undefined, "strategy-option-card");
      if (selected) item.classList.add("strategy-proposal-chosen");
      const header = node("div", undefined, "strategy-goal-heading");
      header.append(node("strong", human(option.action, optionLabels)));
      header.append(node("span", selected ? "Выбран" :
        human(option.status, optionStatusLabels),
        selected ? "strategy-selection-tag" : "strategy-project-state"));
      item.append(header);
      item.append(node("p", human(option.reason, optionReasonLabels), "strategy-option-reason"));
      if (option.source) addField(item, "Источник", option.source);
      if (option.material) addField(item, "Товар / сырьё", human(option.material, commodityLabels));
      if (option.site_id) addField(item, "Стройплощадка", option.site_id);
      addField(item, "Первая оплата", formatNumber(option.first_payment) + " CR");
      addField(item, "Полный бюджет (оценка)", formatNumber(option.total_commitment) + " CR");
      addField(item, "Казна после (прогноз)", formatNumber(option.treasury_after) + " CR");
      if (option.action !== "wait") {
        addField(item, "Оценка задержки", formatNumber(option.estimated_delay_ticks) + " тик.");
        addField(item, "План поставок", formatNumber(option.shipment_count));
        addField(item, "Покрытие потребности", formatNumber(option.covered_units) + " ед.");
        if (Number.isFinite(option.first_purchase_cost))
          addField(item, "Закупка 1-й партии", formatNumber(option.first_purchase_cost) + " CR");
        if (Number.isFinite(option.estimated_net_value))
          addField(item, "Расчётная оценка", formatNumber(option.estimated_net_value));
      }
      target.append(item);
    }
    addNote(target, "Покрытие потребности — прогнозируемый эффект, НЕ фактический размер партии. " +
      "Полный бюджет не означает, что все будущие платежи уже зарезервированы. " +
      "Выбранный вариант не равен завершённому контракту.");
  }
  const proposals = Array.isArray(head.proposals) ? head.proposals : [];
  const label = node("h4", "ПРЕДЛОЖЕНИЯ АДМИНИСТРАТОРОВ", "strategy-subheading");
  target.append(label);
  if (!proposals.length) return addNote(target, "Предложения в последнем цикле не переданы.");
  for (const proposal of proposals) {
    const selected = proposal.administrator === head.selected_administrator;
    const item = node("article", undefined, "strategy-proposal-card");
    if (selected) item.classList.add("strategy-proposal-chosen");
    const row = node("div", undefined, "strategy-goal-heading");
    row.append(node("strong", human(proposal.administrator, administratorLabels)));
    row.append(node("span", selected ? "Выбран" :
      human(proposal.status, decisionLabels), selected ? "strategy-selection-tag" : "strategy-project-state"));
    item.append(row);
    if (proposal.goal) item.append(node("div",
      human(proposal.goal.commodity, commodityLabels) + " → " + text(proposal.goal.destination),
      "strategy-route"));
    addField(item, "Состояние до выбора",
      human(proposal.status, decisionLabels));
    addField(item, "Основание", human(proposal.reason, reasonLabels));
    addField(item, "Запрошено", formatNumber(proposal.requested_credits) + " CR");
    addField(item, "Уровень приоритета", formatNumber(proposal.priority));
    target.append(item);
  }
  addNote(target, "Предложения показаны ДО исполнения. Реальное выполнение смотри в " +
    "состоянии администратора и статусах контрактов ниже.");
}
function strategyRenderConstruction(faction) {
  const target = elements.construction;
  target.replaceChildren();
  const c = faction.construction;
  if (!c) return showEmpty(target,
    "Сервер ещё не передаёт строительного администратора (S1/S2) " +
    "или первый строительный цикл пока не выполнялся.");
  const card = node("article", undefined, "strategy-construction-card");
  const row = node("div", undefined, "strategy-section-header");
  row.append(node("span", "Последнее решение · тик " + formatNumber(c.observed_tick),
    "strategy-eyebrow"),
    node("span", human(c.status, decisionLabels), "strategy-state"));
  card.append(row);
  card.append(node("p", human(c.reason, reasonLabels), "strategy-decision-reason"));
  if (c.selected_goal) {
    addField(card, "Цель", human(c.selected_goal.goal_id, goalLabels));
    addField(card, "Ресурс", human(c.selected_goal.commodity, commodityLabels));
    addField(card, "Узел", c.selected_goal.destination);
  } else addNote(card, "Активной строительной цели на последнем анализе нет.");
  addField(card, "Тип сооружения", c.facility_type || "—");
  addField(card, "Площадка", c.site_id || "Не создана");
  addField(card, "Контракт на поставку", c.contract_id || "Нет");
  const ratio = progressFraction(c);
  if (ratio !== null && c.site_id) {
    const progress = node("div", undefined, "strategy-site-progress");
    const header = node("div", undefined, "strategy-goal-heading");
    header.append(node("span", "Доставленные материалы"),
      node("strong", formatNumber(c.progress_delivered) + " / " +
        formatNumber(c.progress_required)));
    progress.append(header);
    const bar = document.createElement("progress");
    bar.value = ratio;
    bar.max = 1;
    bar.setAttribute("aria-label", "Прогресс доставки строительных материалов");
    progress.append(bar);
    card.append(progress);
  } else addNote(card, "Прогресс площадки пока недоступен; не следует считать её завершённой.");
  const age = observationAge(snapshot, c);
  if (age !== null && age > 0) addNote(card,
    "Решение принято " + age + " тик. назад; прогресс площадки может быть обновлён отдельно.");
  target.append(card);
}
function renderSummary(faction) {
  const target = elements.summary;
  target.replaceChildren();
  const card = node("section", undefined, "strategy-summary-card");
  const header = node("div", undefined, "strategy-section-header");
  header.append(node("span", "Логистический администратор", "strategy-eyebrow"),
    node("span", human(faction.status, decisionLabels), "strategy-state"));
  card.append(header);
  const name = node("h3", strategyFactionName(faction.faction_id), "strategy-faction-name");
  card.append(name);
  card.append(node("p", human(faction.reason, reasonLabels), "strategy-decision-reason"));
  const metrics = node("div", undefined, "strategy-metrics");
  for (const [label, value] of [
    ["Казна", formatNumber(faction.treasury) + " CR"],
    ["Кандидаты", faction.goals.length],
    ["Проекты в ответе", faction.projects.length]
  ]) {
    const item = node("div", undefined, "strategy-metric");
    item.append(node("span", label), node("strong", value));
    metrics.append(item);
  }
  card.append(metrics);
  addField(card, "Администратор", faction.administrator);
  addField(card, "Тик наблюдения", formatNumber(faction.observed_tick));
  const age = observationAge(snapshot, faction);
  addField(card, "Возраст отчёта", age === null ? "не указан" : age + " тик.");
  if (age !== null && age > 0) {
    addNote(card, "Решение принято на предыдущем цикле анализа. Текущий тик мира может быть новее.");
  }
  target.append(card);
}
function renderGoals(faction) {
  const target = elements.goals;
  target.replaceChildren();
  if (!faction.goals.length) return showEmpty(target, "На последнем анализе кандидаты не сформированы.");
  const selectedKey = goalKey(faction.selected_goal);
  faction.goals.forEach((goal, index) => {
    const card = node("article", undefined, "strategy-goal-card");
    if (goalKey(goal) === selectedKey) card.classList.add("strategy-goal-selected");
    const heading = node("div", undefined, "strategy-goal-heading");
    heading.append(node("span", (index + 1) + ". " + human(goal.goal_id, goalLabels)));
    if (goalKey(goal) === selectedKey) heading.append(node("span", "Выбран", "strategy-selection-tag"));
    card.append(heading);
    const details = node("div", undefined, "strategy-goal-details");
    details.append(
      node("span", human(goal.commodity, commodityLabels) + " → " + text(goal.destination)),
      node("span", "Дефицит: " + formatNumber(goal.shortage_ticks) + " тик.")
    );
    card.append(details);
    const assessment = assessmentForGoal(faction, goal);
    if (assessment) {
      const ready = assessment.reason === "ready";
      card.append(node("div", "Выполнимость: " + human(assessment.reason, reasonLabels),
        ready ? "strategy-assessment ready" : "strategy-assessment blocked"));
      if (assessment.source) card.append(node("div", "Доступный источник: " + assessment.source,
        "strategy-goal-details"));
    } else if (!faction.assessments.length) {
      card.append(node("div", "Оценка выполнимости недоступна (S1).",
        "strategy-goal-details"));
    }
    card.append(node("div", "Оценка приоритета: " + formatNumber(goal.score), "strategy-score"));
    target.append(card);
  });
}
function renderProjects(faction) {
  const target = elements.projects;
  target.replaceChildren();
  if (!faction.projects.length) {
    return showEmpty(target, "Стратегические контракты ещё не наблюдаются. Это не означает, " +
      "что в мире нет обычных контрактов.");
  }
  const groups = projectGroups(faction);
  for (const admin of ["logistics", "construction"]) {
    if (!groups[admin].length) continue;
    target.append(node("h4", human(admin, administratorLabels) +
      " · " + groups[admin].length + " контракт(ов)", "strategy-subheading"));
    for (const project of groups[admin]) {
      const card = node("article", undefined, "strategy-project-card");
      const top = node("div", undefined, "strategy-project-top");
      top.append(node("strong", human(project.commodity, commodityLabels)),
        node("span", human(project.state, projectLabels), "strategy-project-state"));
      card.append(top);
      card.append(node("div", text(project.source) + " → " + text(project.destination),
        "strategy-route"));
      addField(card, "Количество", formatNumber(project.quantity));
      addField(card, "Исполнитель", project.executor_id || "Не назначен");
      addField(card, "Резерв оплаты", formatNumber(project.reserved_credits) + " CR");
      addField(card, "Контракт", project.contract_id);
      target.append(card);
    }
  }
  addNote(target, "Контракты строительства — это доставки грузов. " +
    "Сама стройплощадка и её прогресс показаны отдельно.");
}
function renderHistory() {
  const target = elements.history;
  target.replaceChildren();
  const entries = changes.filter(item => item.faction_id === selectedFaction).slice(0, 50);
  if (!entries.length) {
    return showEmpty(target, "Изменения появятся после следующих опросов. Ранее произошедшие события недоступны.");
  }
  for (const item of entries) {
    const row = node("div", undefined, "strategy-history-row");
    row.append(node("time", "Тик " + formatNumber(item.tick)), node("div", item.message));
    target.append(row);
  }
}
function render() {
  if (!elements) return;
  const scroll = elements.content.scrollTop;
  const active = fillFactionSelect();
  elements.mode.textContent = snapshot?.mode === "execute" ? "EXECUTE · выполнение" :
    snapshot?.mode === "shadow" ? "SHADOW · наблюдение" : "Нет данных";
  elements.mode.dataset.mode = snapshot?.mode || "unknown";
  elements.update.textContent = requestError
    ? "Ошибка получения данных · " + requestError
    : snapshot ? "API v1 · тик " + formatNumber(snapshot.snapshot_tick) : "Ожидание ответа API";
  elements.update.classList.toggle("strategy-error", Boolean(requestError));
  if (active) {
    strategyRenderHead(active);
    renderSummary(active);
    renderGoals(active);
    strategyRenderConstruction(active);
    renderProjects(active);
  } else {
    showEmpty(elements.head, requestError || "Нет сведений о стратегическом управлении.");
    showEmpty(elements.summary, requestError || "Нет сведений о стратегическом управлении.");
    elements.goals.replaceChildren();
    elements.construction.replaceChildren();
    elements.projects.replaceChildren();
  }
  renderHistory();
  elements.content.scrollTop = scroll;
}
async function poll() {
  if (!elements || elements.drawer.hidden || pending || document.hidden) return;
  pending = true;
  try {
    const response = await fetch("/api/strategy", {cache: "no-store"});
    if (!response.ok) throw new Error("HTTP " + response.status);
    const next = parseSnapshot(await response.json());
    if (snapshot && next.snapshot_tick < snapshot.snapshot_tick) {
      // New world or rollback: comparison against previous timeline would be misleading.
      changes = [];
      snapshot = null;
    }
    const additions = observedChanges(snapshot, next);
    if (additions.length) changes = [...additions.reverse(), ...changes].slice(0, 100);
    snapshot = next;
    requestError = null;
  } catch (error) {
    requestError = error instanceof Error ? error.message : String(error);
    // Keep the previous snapshot visible, clearly marked as last known data.
  } finally {
    pending = false;
    render();
  }
}
export function initStrategyPanel(options = {}) {
  if (elements) return;
  getFactions = typeof options.getFactions === "function" ? options.getFactions : getFactions;
  elements = {
    toggle:find("strategy-toggle"), drawer:find("strategy-drawer"),
    backdrop:find("strategy-backdrop"), close:find("strategy-close"),
    mode:find("strategy-mode"), update:find("strategy-update"),
    faction:find("strategy-faction"), content:find("strategy-content"),
    head:find("strategy-head"), summary:find("strategy-summary"),
    goals:find("strategy-goals"), construction:find("strategy-construction"),
    projects:find("strategy-projects"), history:find("strategy-history"),
    clear:find("strategy-clear-history"), refresh:find("strategy-refresh")
  };
  if (Object.values(elements).some(element => !element)) {
    throw new Error("Отсутствует элемент интерфейса стратегии");
  }
  elements.toggle.addEventListener("click", () => setOpen(elements.drawer.hidden));
  elements.close.addEventListener("click", () => setOpen(false));
  elements.backdrop.addEventListener("click", () => setOpen(false));
  elements.faction.addEventListener("change", () => {
    selectedFaction = elements.faction.value;
    render();
  });
  elements.clear.addEventListener("click", () => {changes = [];renderHistory();});
  elements.refresh.addEventListener("click", poll);
  document.addEventListener("keydown", event => {
    if (elements.drawer.hidden) return;
    if (event.key === "Escape") {
      event.preventDefault();
      setOpen(false);
    } else if (event.key === "Tab") {
      // Keep keyboard focus inside the modal; return it to the toggle on close.
      const focusable = [...elements.drawer.querySelectorAll("button:not([disabled]),select:not([disabled])")];
      if (!focusable.length) return;
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault(); last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault(); first.focus();
      }
    }
  });
  window.setInterval(poll, 6000);
  render();
}

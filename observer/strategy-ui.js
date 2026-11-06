// Independent, read-only strategy drawer. No writes to the simulation API.
import {
  parseSnapshot, observedChanges, observationAge, goalKey,
  human, goalLabels, commodityLabels, decisionLabels, reasonLabels, projectLabels
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

function factionName(id) {
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
    factionName(a.faction_id).localeCompare(factionName(b.faction_id), "ru"));
  for (const faction of sorted) {
    select.appendChild(new Option(factionName(faction.faction_id), faction.faction_id));
  }
  const present = sorted.some(f => f.faction_id === current);
  selectedFaction = present ? current : sorted[0].faction_id;
  select.value = selectedFaction;
  return snapshot.factions.find(f => f.faction_id === selectedFaction);
}
function renderSummary(faction) {
  const target = elements.summary;
  target.replaceChildren();
  const card = node("section", undefined, "strategy-summary-card");
  const header = node("div", undefined, "strategy-section-header");
  header.append(node("span", "Состояние управления", "strategy-eyebrow"),
    node("span", human(faction.status, decisionLabels), "strategy-state"));
  card.append(header);
  const name = node("h3", factionName(faction.faction_id), "strategy-faction-name");
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
    card.append(node("div", "Оценка приоритета: " + formatNumber(goal.score), "strategy-score"));
    target.append(card);
  });
}
function renderProjects(faction) {
  const target = elements.projects;
  target.replaceChildren();
  if (!faction.projects.length) {
    return showEmpty(target, "Стратегические контракты ещё не наблюдаются. Это не означает, что нет обычных контрактов.");
  }
  for (const project of faction.projects) {
    const card = node("article", undefined, "strategy-project-card");
    const top = node("div", undefined, "strategy-project-top");
    top.append(node("strong", human(project.commodity, commodityLabels)),
      node("span", human(project.state, projectLabels), "strategy-project-state"));
    card.append(top);
    card.append(node("div", text(project.source) + " → " + text(project.destination), "strategy-route"));
    addField(card, "Количество", formatNumber(project.quantity));
    addField(card, "Исполнитель", project.executor_id || "Не назначен");
    addField(card, "Резерв оплаты", formatNumber(project.reserved_credits) + " CR");
    addField(card, "Контракт", project.contract_id);
    target.append(card);
  }
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
    renderSummary(active);
    renderGoals(active);
    renderProjects(active);
  } else {
    showEmpty(elements.summary, requestError || "Нет сведений о стратегическом управлении.");
    elements.goals.replaceChildren();
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
    summary:find("strategy-summary"), goals:find("strategy-goals"),
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

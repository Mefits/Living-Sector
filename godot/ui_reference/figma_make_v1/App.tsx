import { useMemo, useState } from "react";

type IconName =
  | "colony"
  | "economy"
  | "build"
  | "research"
  | "fleet"
  | "faction"
  | "alert"
  | "planet"
  | "station"
  | "ship"
  | "factory"
  | "close"
  | "chevron"
  | "pin"
  | "search"
  | "pause"
  | "play"
  | "fast";

const paths: Record<IconName, React.ReactNode> = {
  colony: (
    <>
      <circle cx="12" cy="12" r="8" />
      <path d="M4.5 14h15M7 7.5c2 1.5 3.2 4.2 3.2 8.5m6.8-8.2c-2.1 1.6-3.4 4.1-3.4 8.2" />
    </>
  ),
  economy: (
    <>
      <path d="M4 18V9m5 9V5m5 13v-6m5 6V3" />
      <path d="m3 7 5-4 5 6 7-7" />
    </>
  ),
  build: (
    <>
      <path d="M4 20V8l8-5 8 5v12" />
      <path d="M2 20h20M8 20v-6h8v6M7 9h2m6 0h2" />
    </>
  ),
  research: (
    <>
      <circle cx="10" cy="10" r="6" />
      <path d="m14.5 14.5 6 6M8 10h4m-2-2v4" />
    </>
  ),
  fleet: (
    <>
      <path d="m12 3 8 15-8-3-8 3 8-15Z" />
      <path d="M12 8v7" />
    </>
  ),
  faction: (
    <>
      <circle cx="8" cy="8" r="3" />
      <circle cx="17" cy="9" r="2.5" />
      <path d="M3 20c.6-4 2.3-6 5-6s4.4 2 5 6m0-4c1-2 2.4-3 4-3 2.2 0 3.5 1.7 4 5" />
    </>
  ),
  alert: (
    <>
      <path d="M12 3 2.5 20h19L12 3Z" />
      <path d="M12 9v5m0 3v.1" />
    </>
  ),
  planet: (
    <>
      <circle cx="12" cy="12" r="6" />
      <path d="M2 15c4 1 9 0 14-2s7-4 5-5" />
    </>
  ),
  station: (
    <>
      <path d="M7 7h10v10H7zM3 12h4m10 0h4M12 3v4m0 10v4" />
      <circle cx="12" cy="12" r="2" />
    </>
  ),
  ship: (
    <>
      <path d="m4 14 8-11 8 11-8 7-8-7Z" />
      <path d="m8 13 4-2 4 2M12 3v8" />
    </>
  ),
  factory: (
    <>
      <path d="M3 21V9l6 3V8l6 4V5l6 4v12H3Z" />
      <path d="M7 17h2m3 0h2m3 0h2" />
    </>
  ),
  close: (
    <>
      <path d="m6 6 12 12M18 6 6 18" />
    </>
  ),
  chevron: (
    <>
      <path d="m8 10 4 4 4-4" />
    </>
  ),
  pin: (
    <>
      <path d="M12 21s6-6.3 6-12a6 6 0 1 0-12 0c0 5.7 6 12 6 12Z" />
      <circle cx="12" cy="9" r="2" />
    </>
  ),
  search: (
    <>
      <circle cx="10" cy="10" r="6" />
      <path d="m15 15 5 5" />
    </>
  ),
  pause: (
    <>
      <path d="M9 5v14m6-14v14" />
    </>
  ),
  play: <path d="m8 5 11 7-11 7V5Z" />,
  fast: (
    <>
      <path d="m4 6 7 6-7 6V6Zm9 0 7 6-7 6V6Z" />
    </>
  ),
};

function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}

const navItems: { id: WindowId; label: string; icon: IconName; hotkey: string }[] = [
  { id: "colonies", label: "Колонии", icon: "colony", hotkey: "1" },
  { id: "economy", label: "Экономика", icon: "economy", hotkey: "2" },
  { id: "construction", label: "Строительство", icon: "build", hotkey: "3" },
  { id: "research", label: "Исследования", icon: "research", hotkey: "4" },
  { id: "fleets", label: "Флоты", icon: "fleet", hotkey: "5" },
  { id: "factions", label: "Управление", icon: "faction", hotkey: "6" },
];

type WindowId = "colonies" | "economy" | "construction" | "research" | "fleets" | "factions";
type WorkspaceId = WindowId | "facility";
type WorkspaceState = { id: WorkspaceId; tab: string; focus?: string };
type Selection = "earth" | "mars" | "station" | "cargo" | "factory" | null;

const planets = [
  { id: "mercury", name: "Меркурий", orbit: 10, angle: 186, size: 8, color: "#bd775d" },
  { id: "venus", name: "Венера", orbit: 15, angle: 302, size: 10, color: "#c98162" },
  { id: "earth", name: "Земля", orbit: 20, angle: 320, size: 11, color: "#6dbd9a" },
  { id: "mars", name: "Марс", orbit: 27, angle: 312, size: 8, color: "#c59e6d" },
  { id: "jupiter", name: "Юпитер", orbit: 43, angle: 152, size: 16, color: "#c4a070" },
  { id: "saturn", name: "Сатурн", orbit: 63, angle: 308, size: 14, color: "#c9a87d" },
];

function SpaceMap({
  selection,
  onSelect,
}: {
  selection: Selection;
  onSelect: (s: Selection) => void;
}) {
  return (
    <div className="space-map" onClick={() => onSelect(null)}>
      <div className="starfield" />
      <div className="system-caption">
        <b>Солнечная система</b>
        <span>13 объектов · масштаб 1×</span>
      </div>
      <div className="system">
        {[10, 15, 20, 27, 43, 63].map((r) => (
          <div key={r} className="orbit" style={{ width: `${r * 2}%`, height: `${r * 2}%` }} />
        ))}
        <button className="sun" title="Солнце" onClick={(e) => e.stopPropagation()}>
          <i />
          <span>Солнце</span>
        </button>
        {planets.map((p) => {
          const rad = (p.angle * Math.PI) / 180;
          const x = 50 + p.orbit * Math.cos(rad);
          const y = 50 + p.orbit * Math.sin(rad);
          const selectable = p.id === "earth" || p.id === "mars";
          return (
            <button
              key={p.id}
              className={`planet-node ${selection === p.id ? "selected" : ""}`}
              style={{ left: `${x}%`, top: `${y}%` }}
              onClick={(e) => {
                e.stopPropagation();
                if (selectable) onSelect(p.id as Selection);
              }}
              title={`${p.name}${selectable ? " — открыть сведения" : ""}`}
            >
              <i style={{ width: p.size, height: p.size, background: p.color }} />
              <span>{p.name}</span>
            </button>
          );
        })}
        <button
          className={`station-node ${selection === "station" ? "selected" : ""}`}
          onClick={(e) => {
            e.stopPropagation();
            onSelect("station");
          }}
        >
          <Icon name="station" size={15} />
          <span>Орбитальная станция</span>
        </button>
        <button
          className={`ship-node ${selection === "cargo" ? "selected" : ""}`}
          onClick={(e) => {
            e.stopPropagation();
            onSelect("cargo");
          }}
        >
          <span className="ship-trail" />
          <Icon name="ship" size={14} />
          <label>ТС «Горизонт»</label>
        </button>
        <div className="asteroid a1">
          ◆ <span>Пояс астероидов</span>
        </div>
        <div className="asteroid a2">
          ◆ <span>Группа Гильда</span>
        </div>
        <div className="asteroid a3">
          ◆ <span>Объект Койпера</span>
        </div>
      </div>
      <div className="map-tools">
        <button title="Поиск">
          <Icon name="search" size={16} />
        </button>
        <button title="Центрировать на Земле">
          <Icon name="pin" size={16} />
        </button>
        <span>73%</span>
        <button title="Уменьшить">−</button>
        <button title="Увеличить">+</button>
      </div>
      <div className="map-hint">Колесо: масштаб · зажать: переместить · объект: выбрать</div>
    </div>
  );
}

function Resource({
  icon,
  label,
  value,
  trend,
  warn,
}: {
  icon: string;
  label: string;
  value: string;
  trend: string;
  warn?: boolean;
}) {
  return (
    <button
      className={`resource ${warn ? "warn" : ""}`}
      title={`${label}: ${value}, изменение ${trend} за цикл`}
    >
      <span className="resource-icon">{icon}</span>
      <span>
        <small>{label}</small>
        <b>{value}</b>
      </span>
      <em>{trend}</em>
    </button>
  );
}

function TopBar({
  paused,
  setPaused,
  speed,
  setSpeed,
  openAlerts,
}: {
  paused: boolean;
  setPaused: (v: boolean) => void;
  speed: number;
  setSpeed: (v: number) => void;
  openAlerts: () => void;
}) {
  return (
    <header className="topbar">
      <div className="brand">
        <span className="brand-mark">LS</span>
        <div>
          <b>LIVING SECTOR</b>
          <small>СОЛ · НАБЛЮДЕНИЕ</small>
        </div>
      </div>
      <div className="resources">
        <Resource icon="●" label="Население" value="150" trend="+2" />
        <Resource icon="◒" label="Еда" value="4 999" trend="+38" />
        <Resource icon="▽" label="Вода" value="2 840" trend="+12" />
        <Resource icon="ϟ" label="Энергия" value="1 324" trend="+24" />
        <Resource icon="₡" label="Экономика" value="84,2K" trend="+3,7%" />
        <Resource icon="⬡" label="Сплавы" value="246" trend="-8" warn />
      </div>
      <div className="top-actions">
        <button className="alert-button" onClick={openAlerts}>
          <Icon name="alert" size={17} />
          <span>3</span>
        </button>
        <div className="date">
          <b>18 МАРТА 2247</b>
          <small>ЦИКЛ 3228</small>
        </div>
        <div className="time-controls">
          <button
            className={paused ? "active" : ""}
            onClick={() => setPaused(!paused)}
            title={paused ? "Продолжить" : "Пауза"}
          >
            <Icon name={paused ? "play" : "pause"} size={15} />
          </button>
          {[1, 2, 3].map((v) => (
            <button
              key={v}
              className={!paused && speed === v ? "active" : ""}
              onClick={() => {
                setSpeed(v);
                setPaused(false);
              }}
            >
              {v === 1 ? "›" : v === 2 ? "»" : "»»"}
            </button>
          ))}
        </div>
      </div>
    </header>
  );
}

function LeftNav({ active, onOpen }: { active: WindowId | null; onOpen: (id: WindowId) => void }) {
  return (
    <nav className="leftnav">
      {navItems.map((item) => (
        <button
          key={item.id}
          className={active === item.id ? "active" : ""}
          onClick={() => onOpen(item.id)}
          title={`${item.label} [${item.hotkey}]`}
        >
          <Icon name={item.icon} />
          <span>{item.label}</span>
          <kbd>{item.hotkey}</kbd>
        </button>
      ))}
      <div className="nav-spacer" />
      <button title="Журнал событий">
        <span className="journal">≡</span>
        <span>Журнал</span>
      </button>
    </nav>
  );
}

function OutlinerGroup({
  title,
  count,
  children,
  defaultOpen = true,
}: {
  title: string;
  count: number;
  children: React.ReactNode;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <section className="out-group">
      <button className="group-head" onClick={() => setOpen(!open)}>
        <Icon name="chevron" size={15} />
        <b>{title}</b>
        <span>{count}</span>
      </button>
      {open && <div className="group-items">{children}</div>}
    </section>
  );
}

function OutlineItem({
  icon,
  name,
  detail,
  status,
  active,
  warn,
  onClick,
}: {
  icon: IconName;
  name: string;
  detail: string;
  status?: string;
  active?: boolean;
  warn?: boolean;
  onClick: () => void;
}) {
  return (
    <button className={`outline-item ${active ? "active" : ""}`} onClick={onClick}>
      <span className={`item-icon ${warn ? "warn" : ""}`}>
        <Icon name={icon} size={16} />
      </span>
      <span className="item-copy">
        <b>{name}</b>
        <small>{detail}</small>
      </span>
      {status && <em className={warn ? "warn-text" : ""}>{status}</em>}
    </button>
  );
}

function Outliner({
  collapsed,
  setCollapsed,
  selection,
  setSelection,
  openWindow,
}: {
  collapsed: boolean;
  setCollapsed: (v: boolean) => void;
  selection: Selection;
  setSelection: (v: Selection) => void;
  openWindow: (v: WindowId) => void;
}) {
  if (collapsed)
    return (
      <button
        className="outliner-open"
        onClick={() => setCollapsed(false)}
        title="Открыть аутлайнер"
      >
        <span>‹</span>
        <small>ОБЪЕКТЫ</small>
      </button>
    );
  return (
    <aside className="outliner">
      <header>
        <div>
          <small>СЕКТОР СОЛ</small>
          <b>Аутлайнер</b>
        </div>
        <button onClick={() => setCollapsed(true)} title="Свернуть">
          ›
        </button>
      </header>
      <div className="out-filter">
        <button className="active">Все</button>
        <button>Гражд.</button>
        <button>Воен.</button>
      </div>
      <div className="out-scroll">
        <OutlinerGroup title="КОЛОНИИ" count={2}>
          <OutlineItem
            icon="planet"
            name="Земля"
            detail="Столица · 150 млн"
            status="92%"
            active={selection === "earth"}
            onClick={() => setSelection("earth")}
          />
          <OutlineItem
            icon="planet"
            name="Марс"
            detail="Форпост · 12 млн"
            status="61%"
            active={selection === "mars"}
            onClick={() => setSelection("mars")}
          />
        </OutlinerGroup>
        <OutlinerGroup title="ПРОИЗВОДСТВО" count={4}>
          <OutlineItem
            icon="factory"
            name="Завод «Вектор»"
            detail="Промышленность · Земля"
            status="ДЕФИЦИТ"
            warn
            active={selection === "factory"}
            onClick={() => setSelection("factory")}
          />
          <OutlineItem icon="factory" name="Горный комплекс" detail="Добыча · Луна" status="+18" />
        </OutlinerGroup>
        <OutlinerGroup title="СТАНЦИИ" count={1}>
          <OutlineItem
            icon="station"
            name="Станция «Зенит»"
            detail="Орбита Земли"
            status="100%"
            active={selection === "station"}
            onClick={() => setSelection("station")}
          />
        </OutlinerGroup>
        <OutlinerGroup title="КОРАБЛИ" count={3}>
          <OutlineItem
            icon="ship"
            name="ТС «Горизонт»"
            detail="Грузовой · следует к Земле"
            status="03:42"
            active={selection === "cargo"}
            onClick={() => setSelection("cargo")}
          />
          <OutlineItem
            icon="ship"
            name="СК «Рубеж»"
            detail="Патруль · орбита Марса"
            status="ГОТОВ"
          />
        </OutlinerGroup>
        <OutlinerGroup title="СТРОИТЕЛЬСТВО" count={2}>
          <OutlineItem
            icon="build"
            name="Солнечный массив"
            detail="Станция «Зенит»"
            status="68%"
            onClick={() => openWindow("construction")}
          />
          <OutlineItem
            icon="build"
            name="Склад сплавов"
            detail="Земля"
            status="14%"
            onClick={() => openWindow("construction")}
          />
        </OutlinerGroup>
      </div>
    </aside>
  );
}

const selectionData = {
  earth: {
    icon: "planet" as IconName,
    type: "КОЛОНИЯ · SOL III",
    name: "Земля",
    sub: "Столица Сектора Сол",
    action: "Управление колонией",
  },
  mars: {
    icon: "planet" as IconName,
    type: "КОЛОНИЯ · SOL IV",
    name: "Марс",
    sub: "Развивающийся форпост",
    action: "Управление колонией",
  },
  station: {
    icon: "station" as IconName,
    type: "ОРБИТАЛЬНАЯ СТАНЦИЯ",
    name: "Станция «Зенит»",
    sub: "Гражданская орбита Земли",
    action: "Управление станцией",
  },
  cargo: {
    icon: "ship" as IconName,
    type: "ГРАЖДАНСКИЙ КОРАБЛЬ",
    name: "ТС «Горизонт»",
    sub: "Капитан А. Воронова",
    action: "Открыть маршрут",
  },
  factory: {
    icon: "factory" as IconName,
    type: "ПРОМЫШЛЕННЫЙ ОБЪЕКТ",
    name: "Завод «Вектор»",
    sub: "Промышленный пояс · Земля",
    action: "Диагностика",
  },
};

function ContextPanel({
  selection,
  onClose,
  openWindow,
}: {
  selection: Exclude<Selection, null>;
  onClose: () => void;
  openWindow: (v: WorkspaceId, tab?: string) => void;
}) {
  const d = selectionData[selection];
  const isCargo = selection === "cargo";
  const isFactory = selection === "factory";
  return (
    <section className="context-panel">
      <header>
        <span className="context-icon">
          <Icon name={d.icon} />
        </span>
        <div>
          <small>{d.type}</small>
          <b>{d.name}</b>
        </div>
        <button onClick={onClose}>
          <Icon name="close" size={17} />
        </button>
      </header>
      <div className="context-body">
        <p className="context-sub">{d.sub}</p>
        {isCargo ? (
          <>
            <div className="route">
              <span>СТАНЦИЯ «ЗЕНИТ»</span>
              <i>
                <em style={{ left: "66%" }} />
              </i>
              <span>ЗЕМЛЯ</span>
            </div>
            <div className="stat-grid">
              <div>
                <small>ГРУЗ</small>
                <b>120 ед. сплавов</b>
              </div>
              <div>
                <small>ПРИБЫТИЕ</small>
                <b>03:42</b>
              </div>
              <div>
                <small>СКОРОСТЬ</small>
                <b>0,18 а.е./д</b>
              </div>
              <div>
                <small>СОСТОЯНИЕ</small>
                <b className="good">Норма</b>
              </div>
            </div>
          </>
        ) : isFactory ? (
          <>
            <div className="warning-box">
              <Icon name="alert" />
              <div>
                <b>Производство остановлено</b>
                <span>Недостаточно промышленных сплавов</span>
              </div>
            </div>
            <div className="flow-row">
              <div>
                <small>ТРЕБУЕТСЯ</small>
                <b>
                  12 <em>сплавов</em>
                </b>
              </div>
              <span>→</span>
              <div>
                <small>В НАЛИЧИИ</small>
                <b className="bad">
                  4 <em>сплава</em>
                </b>
              </div>
            </div>
            <p className="diagnosis">Ближайшая поставка: ТС «Горизонт», прибытие через 03:42.</p>
          </>
        ) : selection === "earth" ? (
          <>
            <div className="stat-grid">
              <div>
                <small>НАСЕЛЕНИЕ</small>
                <b>150 млн</b>
              </div>
              <div>
                <small>СТАБИЛЬНОСТЬ</small>
                <b className="good">92%</b>
              </div>
              <div>
                <small>РАБОЧИЕ</small>
                <b>48 / 52</b>
              </div>
              <div>
                <small>БАЛАНС</small>
                <b className="good">+3,7K</b>
              </div>
            </div>
            <div className="mini-bars">
              <label>
                <span>Еда</span>
                <i>
                  <em style={{ width: "84%" }} />
                </i>
                <b>84%</b>
              </label>
              <label>
                <span>Энергия</span>
                <i>
                  <em style={{ width: "67%" }} />
                </i>
                <b>67%</b>
              </label>
            </div>
          </>
        ) : (
          <>
            <div className="stat-grid">
              <div>
                <small>ЭКИПАЖ</small>
                <b>{selection === "mars" ? "12 млн" : "326"}</b>
              </div>
              <div>
                <small>СОСТОЯНИЕ</small>
                <b className="good">{selection === "mars" ? "61%" : "100%"}</b>
              </div>
            </div>
          </>
        )}
      </div>
      <footer>
        <button
          onClick={() =>
            openWindow(
              isCargo ? "fleets" : isFactory ? "facility" : "colonies",
              isCargo ? "cargo" : isFactory ? "process" : "overview",
            )
          }
        >
          {d.action}
        </button>
        <button className="icon-only" title="Центрировать">
          <Icon name="pin" size={16} />
        </button>
      </footer>
    </section>
  );
}

function ColonyContent({ onSelectFactory }: { onSelectFactory: () => void }) {
  const [tab, setTab] = useState("overview");
  return (
    <>
      <div className="window-tabs">
        <button className={tab === "overview" ? "active" : ""} onClick={() => setTab("overview")}>
          Обзор
        </button>
        <button className={tab === "industry" ? "active" : ""} onClick={() => setTab("industry")}>
          Производство
        </button>
        <button
          className={tab === "population" ? "active" : ""}
          onClick={() => setTab("population")}
        >
          Население
        </button>
      </div>
      {tab === "overview" && (
        <div className="colony-overview">
          <div className="colony-summary">
            <div className="earth-visual">
              <span />
              <i />
              <b>ЗЕМЛЯ</b>
            </div>
            <div className="summary-stats">
              <small>СТОЛИЦА СЕКТОРА</small>
              <h3>Земля</h3>
              <p>Умеренный континентальный мир</p>
              <div>
                <b>
                  150 млн <small>население</small>
                </b>
                <b>
                  92% <small>стабильность</small>
                </b>
                <b>
                  8 <small>районов</small>
                </b>
              </div>
            </div>
          </div>
          <div className="districts">
            <h4>
              РАЙОНЫ И ОБЪЕКТЫ <span>8 / 12</span>
            </h4>
            <div className="district-grid">
              <button>
                <Icon name="factory" />
                <span>
                  Горный комплекс<small>Производство: +18 руды</small>
                </span>
                <em className="ok-dot" />
              </button>
              <button>
                <Icon name="factory" />
                <span>
                  Перерабатывающий цех<small>Производство: +8 сплавов</small>
                </span>
                <em className="ok-dot" />
              </button>
              <button>
                <span className="crop-icon">Y</span>
                <span>
                  Агрокомплекс<small>Производство: +38 еды</small>
                </span>
                <em className="ok-dot" />
              </button>
              <button className="problem" onClick={onSelectFactory}>
                <Icon name="factory" />
                <span>
                  Завод «Вектор»<small>Остановка производства</small>
                </span>
                <Icon name="alert" size={16} />
              </button>
            </div>
          </div>
        </div>
      )}
      {tab === "industry" && <EconomyContent onSelectFactory={onSelectFactory} />}
      {tab === "population" && (
        <div className="placeholder-panel">
          <b>150 млн жителей</b>
          <p>Занятость 92% · доступно 4 рабочих места</p>
          <div className="big-bar">
            <i style={{ width: "92%" }} />
          </div>
        </div>
      )}
    </>
  );
}

function EconomyContent({ onSelectFactory }: { onSelectFactory: () => void }) {
  return (
    <div className="economy-content">
      <div className="economy-kpis">
        <div>
          <small>ВАЛОВОЙ ПРОДУКТ</small>
          <b>84 240 ₡</b>
          <em>+3,7%</em>
        </div>
        <div>
          <small>ТОРГОВЫЙ БАЛАНС</small>
          <b>+12 480 ₡</b>
          <em>Профицит</em>
        </div>
        <div className="warning">
          <small>НЕВЫПОЛНЕННЫЕ ЗАКАЗЫ</small>
          <b>3</b>
          <em>Требуют внимания</em>
        </div>
      </div>
      <div className="production-table">
        <header>
          <span>ПРОИЗВОДСТВЕННАЯ ЦЕПОЧКА</span>
          <span>ВХОД</span>
          <span>ВЫХОД</span>
          <span>СТАТУС</span>
        </header>
        <button>
          <b>Горный комплекс</b>
          <span>−12 энергии</span>
          <span>+18 руды</span>
          <em className="status-ok">РАБОТАЕТ</em>
        </button>
        <button>
          <b>Перерабатывающий цех</b>
          <span>−16 руды</span>
          <span>+8 сплавов</span>
          <em className="status-ok">РАБОТАЕТ</em>
        </button>
        <button className="problem" onClick={onSelectFactory}>
          <b>Завод «Вектор»</b>
          <span>−12 сплавов</span>
          <span>+4 деталей</span>
          <em className="status-bad">ДЕФИЦИТ</em>
        </button>
        <button>
          <b>Агрокомплекс</b>
          <span>−8 воды</span>
          <span>+38 еды</span>
          <em className="status-ok">РАБОТАЕТ</em>
        </button>
      </div>
    </div>
  );
}

function ConstructionContent() {
  return (
    <div className="construction-content">
      <div className="queue">
        <h4>ОЧЕРЕДЬ СТРОИТЕЛЬСТВА</h4>
        <article>
          <span className="build-icon">
            <Icon name="build" />
          </span>
          <div>
            <b>Солнечный массив</b>
            <small>Станция «Зенит» · орбита Земли</small>
            <i>
              <em style={{ width: "68%" }} />
            </i>
          </div>
          <strong>
            68%<small>12 циклов</small>
          </strong>
        </article>
        <article>
          <span className="build-icon">
            <Icon name="factory" />
          </span>
          <div>
            <b>Склад промышленных сплавов</b>
            <small>Промышленный пояс · Земля</small>
            <i>
              <em style={{ width: "14%" }} />
            </i>
          </div>
          <strong>
            14%<small>28 циклов</small>
          </strong>
        </article>
      </div>
      <aside className="build-stock">
        <h4>МАТЕРИАЛЫ</h4>
        <p>
          <span>Промышленные сплавы</span>
          <b className="bad">246 / 480</b>
        </p>
        <p>
          <span>Композиты</span>
          <b>810 / 600</b>
        </p>
        <p>
          <span>Энергомодули</span>
          <b>92 / 90</b>
        </p>
        <div className="warning-box">
          <Icon name="alert" />
          <div>
            <b>Риск задержки</b>
            <span>Запаса сплавов хватит на 8 циклов</span>
          </div>
        </div>
      </aside>
    </div>
  );
}

function ManagementWindow({
  id,
  onClose,
  onSelectFactory,
}: {
  id: WindowId;
  onClose: () => void;
  onSelectFactory: () => void;
}) {
  const titles: Record<WindowId, [string, string, IconName]> = {
    colonies: ["Колонии", "2 активные колонии", "colony"],
    economy: ["Экономика", "Сектор Сол · текущий цикл", "economy"],
    construction: ["Строительство", "2 объекта в очереди", "build"],
    research: ["Исследования", "Прикладная физика", "research"],
    fleets: ["Флоты и маршруты", "1 активный транспорт", "fleet"],
    factions: ["Фракции", "3 политические группы", "faction"],
  };
  const [title, sub, icon] = titles[id];
  return (
    <section className={`management-window window-${id}`}>
      <header className="window-title">
        <span>
          <Icon name={icon} />
        </span>
        <div>
          <b>{title}</b>
          <small>{sub}</small>
        </div>
        <button onClick={onClose}>
          <Icon name="close" />
        </button>
      </header>
      <div className="window-content">
        {id === "colonies" && <ColonyContent onSelectFactory={onSelectFactory} />}
        {id === "economy" && <EconomyContent onSelectFactory={onSelectFactory} />}
        {id === "construction" && <ConstructionContent />}
        {id === "research" && (
          <div className="research-view">
            <div className="tech active">
              <small>ТЕКУЩЕЕ ИССЛЕДОВАНИЕ</small>
              <Icon name="research" size={30} />
              <b>Эффективные энергосети</b>
              <p>Снижение потерь энергии в колониальных сетях.</p>
              <i>
                <em style={{ width: "72%" }} />
              </i>
              <span>72% · 14 циклов</span>
            </div>
            <div className="tech">
              <small>СЛЕДУЮЩЕЕ</small>
              <b>Орбитальная логистика</b>
              <p>+15% к скорости погрузки гражданских судов.</p>
            </div>
          </div>
        )}
        {id === "fleets" && (
          <div className="fleet-view">
            <div className="ship-card">
              <Icon name="ship" size={32} />
              <div>
                <small>ГРУЗОВОЙ ТРАНСПОРТ</small>
                <b>ТС «Горизонт»</b>
                <span>Станция «Зенит» → Земля</span>
              </div>
              <em>В ПУТИ</em>
            </div>
            <div className="route large">
              <span>ЗЕНИТ</span>
              <i>
                <em style={{ left: "66%" }} />
              </i>
              <span>ЗЕМЛЯ</span>
            </div>
            <div className="manifest">
              <b>МАНИФЕСТ ГРУЗА</b>
              <p>
                <span>Промышленные сплавы</span>
                <strong>120 ед.</strong>
              </p>
              <p>
                <span>Приоритет доставки</span>
                <strong>Высокий</strong>
              </p>
              <p>
                <span>Расчётное прибытие</span>
                <strong>03:42</strong>
              </p>
            </div>
          </div>
        )}
        {id === "factions" && (
          <div className="factions-view">
            {[
              ["Союз колонистов", "42%", "Стабильность и развитие колоний"],
              ["Промышленная лига", "35%", "Расширение производства"],
              ["Фронтир", "23%", "Экспансия за пределы Марса"],
            ].map((f, i) => (
              <article key={f[0]}>
                <span className={`faction-mark f${i}`} />
                <div>
                  <b>{f[0]}</b>
                  <p>{f[2]}</p>
                </div>
                <strong>
                  {f[1]}
                  <small>поддержка</small>
                </strong>
              </article>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

const workspaceMeta: Record<WorkspaceId, { title: string; scope: string; icon: IconName }> = {
  colonies: { title: "Колония", scope: "Земля", icon: "colony" },
  facility: { title: "Объект", scope: "Завод «Вектор»", icon: "factory" },
  economy: { title: "Экономика сектора", scope: "Сол · все колонии", icon: "economy" },
  construction: { title: "Строительство", scope: "Все активные проекты", icon: "build" },
  fleets: { title: "Флот и логистика", scope: "Гражданские перевозки", icon: "fleet" },
  factions: { title: "Автономное управление", scope: "Планировщик ИИ", icon: "faction" },
  research: { title: "Исследования", scope: "Научная программа", icon: "research" },
};

const workspaceTabs: Record<WorkspaceId, { id: string; label: string }[]> = {
  colonies: [
    { id: "overview", label: "Обзор и проблемы" },
    { id: "population", label: "Население и труд" },
    { id: "production", label: "Производственные цепочки" },
    { id: "stocks", label: "Запасы" },
    { id: "construction", label: "Строительство" },
    { id: "logistics", label: "Местная логистика" },
  ],
  facility: [
    { id: "process", label: "Процесс" },
    { id: "workers", label: "Работники и оплата" },
    { id: "stocks", label: "Склад" },
    { id: "suppliers", label: "Поставщики" },
  ],
  economy: [
    { id: "balance", label: "Баланс сектора" },
    { id: "chains", label: "Цепочки" },
    { id: "deficits", label: "Дефициты" },
    { id: "bottlenecks", label: "Узкие места" },
  ],
  construction: [
    { id: "projects", label: "Проекты" },
    { id: "materials", label: "Материалы" },
    { id: "suppliers", label: "Поставщики" },
    { id: "blockers", label: "Блокировки" },
  ],
  fleets: [
    { id: "ships", label: "Корабли" },
    { id: "contracts", label: "Контракты" },
    { id: "cargo", label: "Грузы" },
    { id: "routes", label: "Маршруты" },
    { id: "docking", label: "Стыковка" },
    { id: "deliveries", label: "Поставки" },
  ],
  factions: [
    { id: "priorities", label: "Приоритеты ИИ" },
    { id: "plans", label: "План действий" },
    { id: "reasoning", label: "Обоснование" },
    { id: "consequences", label: "Последствия" },
  ],
  research: [
    { id: "progress", label: "Прогресс" },
    { id: "prerequisites", label: "Предпосылки" },
    { id: "unlocks", label: "Открытия" },
  ],
};

function DenseHeader({ columns }: { columns: string[] }) {
  return (
    <div
      className="dense-row dense-head"
      style={{ gridTemplateColumns: `repeat(${columns.length}, 1fr)` }}
    >
      {columns.map((column) => (
        <span key={column}>{column}</span>
      ))}
    </div>
  );
}

function WorkspaceToolbar({
  filter,
  setFilter,
  children,
}: {
  filter: string;
  setFilter: (value: string) => void;
  children?: React.ReactNode;
}) {
  return (
    <div className="workspace-toolbar">
      <label>
        <Icon name="search" size={14} />
        <input
          value={filter}
          onChange={(event) => setFilter(event.target.value)}
          placeholder="Фильтр по объектам и статусам"
        />
      </label>
      <div className="workspace-toolbar-actions">{children}</div>
    </div>
  );
}

function ColonyWorkspace({
  tab,
  navigate,
  select,
}: {
  tab: string;
  navigate: (id: WorkspaceId, tab: string, focus?: string) => void;
  select: (selection: Selection) => void;
}) {
  if (tab === "overview") {
    return (
      <div className="workspace-grid colony-dashboard">
        <section className="workspace-section span-2">
          <header>
            <b>Состояние колонии</b>
            <span className="status-ok">СТАБИЛЬНО</span>
          </header>
          <div className="metric-strip">
            <div>
              <small>Население</small>
              <b>150 млн</b>
              <em>+2,1%</em>
            </div>
            <div>
              <small>Рабочая сила</small>
              <b>48 / 52</b>
              <em>4 вакансии</em>
            </div>
            <div>
              <small>Довольство</small>
              <b>78%</b>
              <em>+3%</em>
            </div>
            <div>
              <small>Бюджет</small>
              <b>+3 720 ₡</b>
              <em>за цикл</em>
            </div>
          </div>
        </section>
        <section className="workspace-section span-2">
          <header>
            <b>Проблемы, наблюдаемые ИИ</b>
            <span>2 активные</span>
          </header>
          <button
            className="issue-line critical"
            onClick={() => navigate("economy", "chains", "alloys")}
          >
            <Icon name="alert" />
            <span>
              <b>Дефицит промышленных сплавов</b>
              <small>Остановлен завод «Вектор» · влияние: −4 детали/цикл</small>
            </span>
            <em>Проследить цепочку →</em>
          </button>
          <button
            className="issue-line"
            onClick={() => navigate("construction", "projects", "solar")}
          >
            <Icon name="build" />
            <span>
              <b>Солнечный массив отстаёт на 6 циклов</b>
              <small>Не подтверждена поставка 234 ед. сплавов</small>
            </span>
            <em>Открыть проект →</em>
          </button>
        </section>
        <section className="workspace-section">
          <header>
            <b>Объекты</b>
            <span>5 действующих</span>
          </header>
          {[
            "Горный комплекс|+18 руды|РАБОТАЕТ",
            "Перерабатывающий цех|+8 сплавов|РАБОТАЕТ",
            "Агрокомплекс|+38 еды|РАБОТАЕТ",
          ].map((row) => {
            const [name, output, status] = row.split("|");
            return (
              <div className="compact-line" key={name}>
                <b>{name}</b>
                <span>{output}</span>
                <em>{status}</em>
              </div>
            );
          })}
          <button
            className="compact-line danger"
            onClick={() => {
              select("factory");
              navigate("facility", "process");
            }}
          >
            <b>Завод «Вектор»</b>
            <span>0 деталей</span>
            <em>ПРОСТОЙ</em>
          </button>
        </section>
        <section className="workspace-section">
          <header>
            <b>Автономное управление</b>
            <button onClick={() => navigate("factions", "plans")}>Все решения →</button>
          </header>
          <div className="ai-note">
            <span>AI</span>
            <p>
              <b>Переназначается грузовой контракт</b>Приоритет доставки сплавов на Землю повышен до
              критического.
            </p>
          </div>
          <div className="ai-note">
            <span>AI</span>
            <p>
              <b>Найм временно ограничен</b>Сохранение резерва рабочей силы для нового склада.
            </p>
          </div>
        </section>
      </div>
    );
  }

  if (tab === "population") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Распределение рабочей силы</b>
            <span>48 занято · 2 свободно · 2 нетрудоспособно</span>
          </header>
          <DenseHeader
            columns={["Сектор", "Работники", "Вакансии", "Средняя оплата", "Эффективность"]}
          />
          {[
            ["Добыча", "12 / 12", "0", "840 ₡", "96%"],
            ["Переработка", "9 / 10", "1", "920 ₡", "89%"],
            ["Промышленность", "14 / 16", "2", "1 120 ₡", "0% · простой"],
            ["Сельское хозяйство", "8 / 8", "0", "780 ₡", "93%"],
            ["Службы", "5 / 6", "1", "760 ₡", "81%"],
          ].map((row) => (
            <div className="dense-row five" key={row[0]}>
              {row.map((cell, index) => (
                <span className={cell.includes("простой") ? "bad" : ""} key={index}>
                  {cell}
                </span>
              ))}
            </div>
          ))}
        </section>
      </div>
    );
  }

  if (tab === "production") {
    return <EconomyWorkspace tab="chains" navigate={navigate} select={select} />;
  }

  if (tab === "stocks") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Склады Земли</b>
            <span>Обновлено цикл 3228</span>
          </header>
          <DenseHeader
            columns={["Ресурс", "В наличии", "Резерв", "Изменение / цикл", "Дней запаса"]}
          />
          {[
            ["Еда", "4 999", "1 200", "+38", "84"],
            ["Вода", "2 840", "900", "+12", "62"],
            ["Руда", "670", "180", "+2", "28"],
            ["Промышленные сплавы", "4", "240", "−8", "< 1"],
            ["Детали", "146", "80", "−4", "11"],
          ].map((row) => (
            <div
              className={`dense-row five ${row[0].includes("сплавы") ? "danger-row" : ""}`}
              key={row[0]}
            >
              {row.map((cell) => (
                <span key={cell}>{cell}</span>
              ))}
            </div>
          ))}
        </section>
      </div>
    );
  }

  if (tab === "construction") return <ConstructionWorkspace tab="projects" navigate={navigate} />;

  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>Местные перевозки</b>
          <span>7 активных маршрутов</span>
        </header>
        <DenseHeader columns={["Маршрут", "Груз", "Частота", "Задержка", "Назначение"]} />
        {[
          ["Шахта → НПЗ", "руда · 16", "каждый цикл", "0", "Переработка"],
          ["НПЗ → Завод", "сплавы · 8", "каждые 2 цикла", "+3 цикла", "Вектор"],
          ["Ферма → Центральный склад", "еда · 38", "каждый цикл", "0", "Население"],
          ["Зенит → Поверхность", "сплавы · 120", "прибытие 03:42", "0", "Завод / стройка"],
        ].map((row) => (
          <div className="dense-row five" key={row[0]}>
            {row.map((cell) => (
              <span key={cell}>{cell}</span>
            ))}
          </div>
        ))}
      </section>
    </div>
  );
}

function EconomyWorkspace({
  tab,
  navigate,
  select,
}: {
  tab: string;
  navigate: (id: WorkspaceId, tab: string, focus?: string) => void;
  select: (selection: Selection) => void;
}) {
  if (tab === "chains") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2 chain-section">
          <header>
            <b>Цепочка промышленных деталей</b>
            <span className="status-bad">РАЗРЫВ</span>
          </header>
          <div className="chain-flow">
            <button>
              <small>ДОБЫЧА</small>
              <Icon name="factory" />
              <b>Горный комплекс</b>
              <span>+18 руды/цикл</span>
              <em>670 на складе</em>
            </button>
            <i>
              →<small>16</small>
            </i>
            <button>
              <small>ПЕРЕРАБОТКА</small>
              <Icon name="factory" />
              <b>Перерабатывающий цех</b>
              <span>+8 сплавов/цикл</span>
              <em>8 зарезервировано</em>
            </button>
            <i className="broken">
              →<small>нужно 12</small>
            </i>
            <button
              className="chain-problem"
              onClick={() => {
                select("factory");
                navigate("facility", "process", "alloys");
              }}
            >
              <small>ПРОИЗВОДСТВО</small>
              <Icon name="alert" />
              <b>Завод «Вектор»</b>
              <span>0 деталей/цикл</span>
              <em>Простой: 3 цикла →</em>
            </button>
          </div>
          <div className="chain-diagnosis">
            <Icon name="alert" />
            <p>
              <b>Причина:</b> завод потребляет 12 сплавов за цикл, локальное производство — 8.
              Контракт LS-044 доставляет ещё 120 ед. через 03:42.
            </p>
            <button onClick={() => navigate("fleets", "cargo", "LS-044")}>Открыть поставку</button>
          </div>
        </section>
        <section className="workspace-section">
          <header>
            <b>Баланс цепочки</b>
            <span>за цикл</span>
          </header>
          <div className="key-value">
            <span>Спрос на сплавы</span>
            <b>20</b>
          </div>
          <div className="key-value">
            <span>Производство</span>
            <b>8</b>
          </div>
          <div className="key-value">
            <span>Дефицит</span>
            <b className="bad">−12</b>
          </div>
          <div className="key-value">
            <span>Внешние поставки</span>
            <b>+120 / 8 циклов</b>
          </div>
        </section>
        <section className="workspace-section">
          <header>
            <b>Решение ИИ</b>
            <button onClick={() => navigate("factions", "reasoning")}>Обоснование →</button>
          </header>
          <div className="ai-note">
            <span>AI</span>
            <p>
              <b>Приоритет LS-044 повышен</b>После прибытия 80 ед. пойдут заводу, 40 ед. —
              строительству.
            </p>
          </div>
        </section>
      </div>
    );
  }

  const rows =
    tab === "deficits"
      ? [
          ["Промышленные сплавы", "−12 / цикл", "Земля", "Критический", "03:42"],
          ["Рабочие", "−4", "Земля", "Средний", "18 циклов"],
          ["Вода", "−2 / цикл", "Марс", "Низкий", "6 циклов"],
        ]
      : tab === "bottlenecks"
        ? [
            ["НПЗ → Завод", "8 / 12", "66%", "Транспорт / выпуск", "LS-044"],
            ["Зенит → Земля", "120 ед.", "очередь 2", "Стыковка", "03:42"],
            ["Марс → Земля", "24 ед.", "72%", "Дальность", "19:20"],
          ]
        : [
            ["Земля", "+84 240 ₡", "+38 еда", "−12 сплавы", "2 проблемы"],
            ["Марс", "+12 410 ₡", "−2 вода", "+6 руда", "1 проблема"],
            ["Станция «Зенит»", "+4 800 ₡", "+24 энергия", "−8 сплавы", "1 проект"],
          ];
  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>
            {tab === "deficits"
              ? "Дефициты сектора"
              : tab === "bottlenecks"
                ? "Узкие места"
                : "Межколониальный баланс"}
          </b>
          <span>Цикл 3228</span>
        </header>
        <DenseHeader
          columns={
            tab === "balance"
              ? ["Узел", "Экономика", "Профицит", "Дефицит", "Состояние"]
              : ["Ресурс / поток", "Величина", "Узел", "Причина / риск", "Разрешение"]
          }
        />
        {rows.map((row) => (
          <button
            className="dense-row five"
            key={row[0]}
            onClick={() => row[0].includes("сплав") && navigate("economy", "chains", "alloys")}
          >
            {row.map((cell) => (
              <span key={cell}>{cell}</span>
            ))}
          </button>
        ))}
      </section>
    </div>
  );
}

function FacilityWorkspace({
  tab,
  navigate,
}: {
  tab: string;
  navigate: (id: WorkspaceId, tab: string, focus?: string) => void;
}) {
  if (tab === "process") {
    return (
      <div className="workspace-grid facility-layout">
        <section className="workspace-section span-2">
          <header>
            <b>Производственный цикл</b>
            <span className="status-bad">ПРОСТОЙ · 3 ЦИКЛА</span>
          </header>
          <div className="facility-process">
            <div className="material missing">
              <small>ВХОД</small>
              <b>Промышленные сплавы</b>
              <strong>4 / 12</strong>
              <span>Не хватает 8 ед.</span>
            </div>
            <i>→</i>
            <div className="machine">
              <Icon name="factory" size={28} />
              <b>Цикл сборки</b>
              <span>1 цикл · 14 работников</span>
              <em>ОЖИДАЕТ РЕСУРС</em>
            </div>
            <i>→</i>
            <div className="material">
              <small>ВЫХОД</small>
              <b>Промышленные детали</b>
              <strong>0 / 4</strong>
              <span>Последний выпуск: цикл 3225</span>
            </div>
          </div>
          <button
            className="root-cause"
            onClick={() => navigate("facility", "suppliers", "alloys")}
          >
            <Icon name="alert" />
            <span>
              <b>Причина простоя: недостаточно входного ресурса</b>
              <small>Локальный НПЗ поставляет 8 из необходимых 12 ед. за цикл.</small>
            </span>
            <em>Проверить поставщиков →</em>
          </button>
        </section>
        <section className="workspace-section">
          <header>
            <b>Смена</b>
            <span>Текущая</span>
          </header>
          <div className="key-value">
            <span>Работники</span>
            <b>14 / 16</b>
          </div>
          <div className="key-value">
            <span>Фонд оплаты</span>
            <b>15 680 ₡</b>
          </div>
          <div className="key-value">
            <span>Средняя оплата</span>
            <b>1 120 ₡</b>
          </div>
          <div className="key-value">
            <span>Эффективность труда</span>
            <b>94%</b>
          </div>
        </section>
        <section className="workspace-section">
          <header>
            <b>Локальный склад</b>
            <button onClick={() => navigate("facility", "stocks")}>Подробнее →</button>
          </header>
          <div className="key-value">
            <span>Сплавы</span>
            <b className="bad">4 / 120</b>
          </div>
          <div className="key-value">
            <span>Детали</span>
            <b>146 / 300</b>
          </div>
          <div className="key-value">
            <span>Энергия</span>
            <b>84 / 90</b>
          </div>
        </section>
      </div>
    );
  }
  if (tab === "suppliers") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Поставщики промышленных сплавов</b>
            <span>Потребность: 12 / цикл</span>
          </header>
          <DenseHeader
            columns={["Поставщик", "Контракт", "Объём", "Следующая поставка", "Надёжность"]}
          />
          <div className="dense-row five">
            <span>Перерабатывающий цех · Земля</span>
            <span>Внутренний</span>
            <span>8 / цикл</span>
            <span>сейчас</span>
            <span>98%</span>
          </div>
          <button
            className="dense-row five selected-row"
            onClick={() => navigate("fleets", "cargo", "LS-044")}
          >
            <span>Станция «Зенит»</span>
            <span>LS-044</span>
            <span>120 ед.</span>
            <span>ТС «Горизонт» · 03:42</span>
            <span>91% →</span>
          </button>
          <div className="dense-row five">
            <span>Марсианский комбинат</span>
            <span>Резервный</span>
            <span>24 ед.</span>
            <span>19:20</span>
            <span>72%</span>
          </div>
        </section>
      </div>
    );
  }
  const rows =
    tab === "workers"
      ? [
          ["Операторы линии", "8 / 8", "1 180 ₡", "96%", "ожидание"],
          ["Техники", "4 / 5", "1 240 ₡", "91%", "дежурство"],
          ["Логистика", "2 / 3", "920 ₡", "87%", "разгрузка"],
        ]
      : [
          ["Промышленные сплавы", "4", "12", "120", "критически мало"],
          ["Промышленные детали", "146", "0", "300", "норма"],
          ["Энергомодули", "84", "6", "90", "норма"],
        ];
  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>{tab === "workers" ? "Работники и заработная плата" : "Склад объекта"}</b>
          <span>Завод «Вектор»</span>
        </header>
        <DenseHeader
          columns={
            tab === "workers"
              ? ["Группа", "Занято", "Оплата", "Квалификация", "Состояние"]
              : ["Ресурс", "В наличии", "На цикл", "Вместимость", "Статус"]
          }
        />
        {rows.map((row) => (
          <div className="dense-row five" key={row[0]}>
            {row.map((cell) => (
              <span key={cell}>{cell}</span>
            ))}
          </div>
        ))}
      </section>
    </div>
  );
}

function ConstructionWorkspace({
  tab,
  navigate,
}: {
  tab: string;
  navigate: (id: WorkspaceId, tab: string, focus?: string) => void;
}) {
  if (tab === "projects") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Активные проекты</b>
            <span>2 проекта · 1 задержан</span>
          </header>
          <DenseHeader
            columns={["Проект", "Расположение", "Прогресс", "Оценка завершения", "Состояние"]}
          />
          <button
            className="dense-row five danger-row"
            onClick={() => navigate("construction", "materials", "solar")}
          >
            <span>Солнечный массив</span>
            <span>Станция «Зенит»</span>
            <span>
              <i className="inline-progress">
                <em style={{ width: "68%" }} />
              </i>
              68%
            </span>
            <span>+6 циклов</span>
            <span>НЕТ МАТЕРИАЛОВ →</span>
          </button>
          <div className="dense-row five">
            <span>Склад сплавов</span>
            <span>Земля</span>
            <span>
              <i className="inline-progress">
                <em style={{ width: "14%" }} />
              </i>
              14%
            </span>
            <span>28 циклов</span>
            <span>Работает</span>
          </div>
        </section>
      </div>
    );
  }
  if (tab === "materials") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Материалы · Солнечный массив</b>
            <span>Прогресс 68%</span>
          </header>
          <DenseHeader columns={["Материал", "Нужно", "Доступно", "В пути", "Недостача"]} />
          <button
            className="dense-row five danger-row"
            onClick={() => navigate("construction", "suppliers", "alloys")}
          >
            <span>Промышленные сплавы</span>
            <span>480</span>
            <span>246</span>
            <span>40 · LS-044</span>
            <span>−194 →</span>
          </button>
          <div className="dense-row five">
            <span>Композиты</span>
            <span>600</span>
            <span>810</span>
            <span>0</span>
            <span>0</span>
          </div>
          <div className="dense-row five">
            <span>Энергомодули</span>
            <span>90</span>
            <span>92</span>
            <span>0</span>
            <span>0</span>
          </div>
        </section>
        <section className="workspace-section span-2">
          <div className="chain-diagnosis">
            <Icon name="alert" />
            <p>
              <b>Блокировка:</b> проект не начнёт следующую фазу без 194 ед. сплавов. ИИ разделил
              прибывающий груз между заводом и проектом.
            </p>
            <button onClick={() => navigate("construction", "suppliers", "alloys")}>
              Найти поставщика
            </button>
          </div>
        </section>
      </div>
    );
  }
  if (tab === "suppliers") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Поставщики для проекта</b>
            <span>Промышленные сплавы · −194</span>
          </header>
          <DenseHeader columns={["Поставщик", "Доступно", "Резерв", "Доставка", "Решение ИИ"]} />
          <div className="dense-row five">
            <span>Перерабатывающий цех · Земля</span>
            <span>8 / цикл</span>
            <span>завод</span>
            <span>локальная</span>
            <span>40% выпуска</span>
          </div>
          <button
            className="dense-row five selected-row"
            onClick={() => navigate("fleets", "cargo", "LS-044")}
          >
            <span>Склад «Зенит»</span>
            <span>120</span>
            <span>LS-044</span>
            <span>ТС «Горизонт» · 03:42</span>
            <span>40 ед. проекту →</span>
          </button>
          <div className="dense-row five">
            <span>Марсианский комбинат</span>
            <span>240</span>
            <span>нет</span>
            <span>19:20</span>
            <span>Запросить 154</span>
          </div>
        </section>
      </div>
    );
  }
  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>Блокировки проектов</b>
          <span>1 критическая</span>
        </header>
        <div className="root-cause">
          <Icon name="alert" />
          <span>
            <b>Солнечный массив · фаза монтажа</b>
            <small>Ожидается 194 ед. промышленных сплавов. Рабочие и док свободны.</small>
          </span>
          <em>Задержка +6 циклов</em>
        </div>
      </section>
    </div>
  );
}

function FleetWorkspace({
  tab,
  navigate,
  select,
}: {
  tab: string;
  navigate: (id: WorkspaceId, tab: string, focus?: string) => void;
  select: (selection: Selection) => void;
}) {
  if (tab === "ships") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Гражданские суда</b>
            <span>3 зарегистрировано</span>
          </header>
          <DenseHeader columns={["Судно", "Класс", "Задача", "Груз", "Статус"]} />
          <button
            className="dense-row five selected-row"
            onClick={() => {
              select("cargo");
              navigate("fleets", "cargo", "LS-044");
            }}
          >
            <span>ТС «Горизонт»</span>
            <span>Грузовой</span>
            <span>LS-044</span>
            <span>120 сплавов</span>
            <span>В пути · 03:42 →</span>
          </button>
          <div className="dense-row five">
            <span>СК «Рубеж»</span>
            <span>Патрульный</span>
            <span>Орбита Марса</span>
            <span>—</span>
            <span>Готов</span>
          </div>
          <div className="dense-row five">
            <span>БТ «Кедр»</span>
            <span>Буксир</span>
            <span>Док «Зенит»</span>
            <span>—</span>
            <span>Стыковка</span>
          </div>
        </section>
      </div>
    );
  }
  if (tab === "cargo") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Груз LS-044</b>
            <span className="status-ok">В ПУТИ</span>
          </header>
          <div className="cargo-manifest">
            <div>
              <small>СУДНО</small>
              <b>ТС «Горизонт»</b>
              <span>Капитан А. Воронова</span>
            </div>
            <div>
              <small>ГРУЗ</small>
              <b>120 ед. сплавов</b>
              <span>масса 840 т</span>
            </div>
            <div>
              <small>КОНТРАКТ</small>
              <b>LS-044</b>
              <span>критический приоритет</span>
            </div>
            <div>
              <small>ПРИБЫТИЕ</small>
              <b>03:42</b>
              <span>без задержки</span>
            </div>
          </div>
          <button className="route-workflow" onClick={() => navigate("fleets", "routes", "LS-044")}>
            <span>
              <Icon name="station" />
              Станция «Зенит»<small>отправлено 18:20</small>
            </span>
            <i>
              <em style={{ left: "66%" }} />
            </i>
            <span>
              <Icon name="planet" />
              Земля<small>док E-4 · 03:42</small>
            </span>
          </button>
          <div className="allocation">
            <b>ПЛАН РАСПРЕДЕЛЕНИЯ ПОСЛЕ ПРИБЫТИЯ</b>
            <span>80 ед. → Завод «Вектор»</span>
            <span>40 ед. → Солнечный массив</span>
          </div>
        </section>
      </div>
    );
  }
  if (tab === "routes") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Маршрут LS-044</b>
            <span>Зенит → Земля · 66%</span>
          </header>
          <div className="route-detail">
            <div>
              <small>01</small>
              <b>Станция «Зенит»</b>
              <span>Погрузка завершена · док Z-2</span>
            </div>
            <i />
            <div>
              <small>02</small>
              <b>Трансферная орбита</b>
              <span>Текущий участок · скорость 0,18 а.е./д</span>
            </div>
            <i />
            <button
              onClick={() => {
                select("earth");
                navigate("colonies", "logistics", "destination");
              }}
            >
              <small>03</small>
              <b>Земля · док E-4</b>
              <span>Назначение · открыть колонию →</span>
            </button>
          </div>
        </section>
      </div>
    );
  }
  const rows =
    tab === "contracts"
      ? [
          ["LS-044", "Сплавы · 120", "Зенит → Земля", "Критический", "03:42"],
          ["LS-039", "Вода · 80", "Земля → Марс", "Обычный", "19:20"],
          ["LS-046", "Руда · 64", "Луна → Земля", "Высокий", "08:10"],
        ]
      : tab === "docking"
        ? [
            ["Зенит Z-2", "свободен", "Горизонт", "отправлен", "—"],
            ["Земля E-4", "зарезервирован", "Горизонт", "03:42", "разгрузка 01:20"],
            ["Марс M-1", "занят", "Кедр", "06:10", "ремонт"],
          ]
        : [
            ["LS-044", "120 сплавов", "Земля", "03:42", "по графику"],
            ["LS-046", "64 руды", "Земля", "08:10", "+1 цикл"],
            ["LS-039", "80 воды", "Марс", "19:20", "по графику"],
          ];
  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>
            {tab === "contracts"
              ? "Транспортные контракты"
              : tab === "docking"
                ? "Стыковочные операции"
                : "Предстоящие поставки"}
          </b>
          <span>Автономная диспетчеризация</span>
        </header>
        <DenseHeader
          columns={[
            "Идентификатор",
            "Груз / статус",
            "Маршрут / судно",
            "Приоритет / время",
            "Результат",
          ]}
        />
        {rows.map((row) => (
          <div className="dense-row five" key={row[0]}>
            {row.map((cell) => (
              <span key={cell}>{cell}</span>
            ))}
          </div>
        ))}
      </section>
    </div>
  );
}

function AdministrationWorkspace({ tab }: { tab: string }) {
  const plans = [
    ["1", "Доставить сплавы на Землю", "Выполняется", "Возобновит завод через 4 цикла"],
    ["2", "Разделить груз LS-044: 80 / 40", "Запланировано", "Стройка отстанет ещё на 6 циклов"],
    ["3", "Заключить контракт с Марсом на 154 сплава", "Оценка", "Расход +8 400 ₡"],
    ["4", "Не расширять штат завода", "Действует", "Сохранит фонд оплаты 2 240 ₡"],
  ];
  if (tab === "priorities") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Приоритеты планировщика</b>
            <span>Режим: наблюдение</span>
          </header>
          {[
            ["Обеспечение населения", 92],
            ["Устранение производственных простоев", 88],
            ["Завершение орбитальной энергетики", 64],
            ["Накопление резервов", 48],
            ["Экспансия Марса", 31],
          ].map(([name, value]) => (
            <div className="priority-line" key={String(name)}>
              <span>{name}</span>
              <i>
                <em style={{ width: `${value}%` }} />
              </i>
              <b>{value}</b>
            </div>
          ))}
        </section>
      </div>
    );
  }
  if (tab === "reasoning") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2 reasoning-log">
          <header>
            <b>Обоснование решения · дефицит сплавов</b>
            <span>Цикл 3228.41</span>
          </header>
          <p>
            <b>Наблюдение</b>Завод «Вектор» простаивает 3 цикла. Потеря: 12 деталей.
          </p>
          <p>
            <b>Ограничения</b>На Земле 4 сплава. НПЗ выпускает 8 при спросе 20. Солнечный массив
            требует ещё 194.
          </p>
          <p>
            <b>Рассмотрено</b>Остановить стройку; купить у Марса; перенаправить LS-044; увеличить
            выпуск НПЗ.
          </p>
          <p className="chosen">
            <b>Выбрано</b>Перенаправить 80 ед. груза заводу и 40 ед. строительству. Одновременно
            запросить 154 ед. у Марса.
          </p>
          <p>
            <b>Почему</b>Простой завода создаёт каскадный дефицит деталей через 11 циклов. Задержка
            стройки допустима до 9 циклов.
          </p>
        </section>
      </div>
    );
  }
  if (tab === "consequences") {
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Прогноз последствий</b>
            <span>Горизонт: 24 цикла</span>
          </header>
          <DenseHeader
            columns={["Показатель", "Без действия", "Текущий план", "Разница", "Уверенность"]}
          />
          {[
            ["Выпуск деталей", "−96", "−16", "+80", "92%"],
            ["Срок солнечного массива", "+18 циклов", "+6 циклов", "−12", "78%"],
            ["Бюджет сектора", "+4 100 ₡", "−4 300 ₡", "−8 400", "96%"],
            ["Стабильность Земли", "−6%", "−1%", "+5%", "71%"],
          ].map((row) => (
            <div className="dense-row five" key={row[0]}>
              {row.map((cell) => (
                <span key={cell}>{cell}</span>
              ))}
            </div>
          ))}
        </section>
      </div>
    );
  }
  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>Очередь действий ИИ</b>
          <span>4 решения</span>
        </header>
        <DenseHeader columns={["Порядок", "Действие", "Статус", "Ожидаемое последствие"]} />
        {plans.map((row) => (
          <div className="dense-row four" key={row[0]}>
            {row.map((cell) => (
              <span key={cell}>{cell}</span>
            ))}
          </div>
        ))}
      </section>
    </div>
  );
}

function ResearchWorkspace({ tab }: { tab: string }) {
  if (tab === "progress")
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Эффективные энергосети</b>
            <span>72% · 14 циклов</span>
          </header>
          <div className="research-track">
            <Icon name="research" size={34} />
            <div>
              <b>2 840 / 3 920 очков</b>
              <i>
                <em style={{ width: "72%" }} />
              </i>
              <span>+78 очков за цикл · без задержек</span>
            </div>
          </div>
        </section>
      </div>
    );
  if (tab === "prerequisites")
    return (
      <div className="workspace-grid">
        <section className="workspace-section span-2">
          <header>
            <b>Предпосылки</b>
            <span>3 / 3 выполнено</span>
          </header>
          {[
            "Распределительные сети I · исследовано",
            "Материаловедение · исследовано",
            "Орбитальная энергетика · исследовано",
          ].map((item) => (
            <div className="compact-line" key={item}>
              <b>{item}</b>
              <em>ГОТОВО</em>
            </div>
          ))}
        </section>
      </div>
    );
  return (
    <div className="workspace-grid">
      <section className="workspace-section span-2">
        <header>
          <b>Будет открыто</b>
          <span>После завершения</span>
        </header>
        <div className="unlock-grid">
          <div>
            <b>Умные энергомодули</b>
            <span>+12% к выпуску энергии</span>
          </div>
          <div>
            <b>Перераспределение нагрузки</b>
            <span>−8% потребления объектов</span>
          </div>
          <div>
            <b>Солнечный массив II</b>
            <span>Новый проект станции</span>
          </div>
        </div>
      </section>
    </div>
  );
}

function WorkspaceShell({
  state,
  canGoBack,
  onBack,
  onClose,
  navigate,
  select,
}: {
  state: WorkspaceState;
  canGoBack: boolean;
  onBack: () => void;
  onClose: () => void;
  navigate: (id: WorkspaceId, tab: string, focus?: string) => void;
  select: (selection: Selection) => void;
}) {
  const [filter, setFilter] = useState("");
  const meta = workspaceMeta[state.id];
  const tabs = workspaceTabs[state.id];
  const currentTab = tabs.some((tab) => tab.id === state.tab) ? state.tab : tabs[0].id;
  return (
    <section className="management-window workspace-window">
      <header className="workspace-titlebar">
        <button className="back-button" disabled={!canGoBack} onClick={onBack} title="Назад">
          ‹
        </button>
        <span className="workspace-title-icon">
          <Icon name={meta.icon} />
        </span>
        <div className="workspace-breadcrumbs">
          <small>
            СЕКТОР СОЛ <i>/</i> {meta.title.toUpperCase()}
          </small>
          <b>{meta.scope}</b>
        </div>
        {state.focus && (
          <span className="focus-tag">
            ФОКУС:{" "}
            {state.focus === "LS-044"
              ? "LS-044"
              : state.focus === "solar"
                ? "СОЛНЕЧНЫЙ МАССИВ"
                : "СПЛАВЫ"}
          </span>
        )}
        <button className="workspace-close" onClick={onClose}>
          <Icon name="close" />
        </button>
      </header>
      <div className="workspace-tabs">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            className={currentTab === tab.id ? "active" : ""}
            onClick={() => navigate(state.id, tab.id, state.focus)}
          >
            {tab.label}
          </button>
        ))}
      </div>
      <WorkspaceToolbar filter={filter} setFilter={setFilter}>
        <span>ОБНОВЛЕНО: ЦИКЛ 3228.41</span>
        <button>Экспорт журнала</button>
      </WorkspaceToolbar>
      <div className="workspace-scroll" data-filter={filter}>
        {filter && (
          <div className="filter-results">
            <span>НАЙДЕНО В ТЕКУЩЕМ РАЗДЕЛЕ</span>
            {["Завод «Вектор» · объект", "Промышленные сплавы · ресурс", "LS-044 · контракт"]
              .filter((item) => item.toLowerCase().includes(filter.toLowerCase()))
              .map((item) => (
                <button
                  key={item}
                  onClick={() =>
                    item.startsWith("LS")
                      ? navigate("fleets", "cargo", "LS-044")
                      : item.startsWith("Завод")
                        ? navigate("facility", "process", "alloys")
                        : navigate("economy", "chains", "alloys")
                  }
                >
                  {item}
                </button>
              ))}
            {!["Завод «Вектор» · объект", "Промышленные сплавы · ресурс", "LS-044 · контракт"].some(
              (item) => item.toLowerCase().includes(filter.toLowerCase()),
            ) && <em>Совпадений нет</em>}
          </div>
        )}
        {state.id === "colonies" && (
          <ColonyWorkspace tab={currentTab} navigate={navigate} select={select} />
        )}
        {state.id === "facility" && <FacilityWorkspace tab={currentTab} navigate={navigate} />}
        {state.id === "economy" && (
          <EconomyWorkspace tab={currentTab} navigate={navigate} select={select} />
        )}
        {state.id === "construction" && (
          <ConstructionWorkspace tab={currentTab} navigate={navigate} />
        )}
        {state.id === "fleets" && (
          <FleetWorkspace tab={currentTab} navigate={navigate} select={select} />
        )}
        {state.id === "factions" && <AdministrationWorkspace tab={currentTab} />}
        {state.id === "research" && <ResearchWorkspace tab={currentTab} />}
      </div>
    </section>
  );
}

function Alerts({
  onClose,
  investigateShortage,
  openConstruction,
  followShip,
}: {
  onClose: () => void;
  investigateShortage: () => void;
  openConstruction: () => void;
  followShip: () => void;
}) {
  return (
    <section className="alerts-popover">
      <header>
        <div>
          <small>ЖУРНАЛ СЕКТОРА</small>
          <b>Требуют внимания</b>
        </div>
        <button onClick={onClose}>
          <Icon name="close" />
        </button>
      </header>
      <button className="critical" onClick={investigateShortage}>
        <Icon name="alert" />
        <div>
          <b>Дефицит промышленных сплавов</b>
          <p>Завод «Вектор» остановил производство.</p>
          <small>2 мин. назад · Земля</small>
        </div>
        <span>Открыть</span>
      </button>
      <button onClick={openConstruction}>
        <Icon name="build" />
        <div>
          <b>Риск задержки строительства</b>
          <p>Солнечный массив: запасов хватит на 8 циклов.</p>
          <small>Цикл 3227 · Станция «Зенит»</small>
        </div>
        <span>Открыть</span>
      </button>
      <button onClick={followShip}>
        <Icon name="ship" />
        <div>
          <b>Транспорт приближается</b>
          <p>ТС «Горизонт» прибудет через 03:42.</p>
          <small>Цикл 3227 · Земля</small>
        </div>
        <span>Следить</span>
      </button>
    </section>
  );
}

export default function App() {
  const [selection, setSelection] = useState<Selection>(null);
  const [workspace, setWorkspace] = useState<WorkspaceState | null>(null);
  const [workspaceHistory, setWorkspaceHistory] = useState<WorkspaceState[]>([]);
  const [outlinerCollapsed, setOutlinerCollapsed] = useState(false);
  const [alerts, setAlerts] = useState(false);
  const [paused, setPaused] = useState(true);
  const [speed, setSpeed] = useState(1);
  const status = useMemo(() => (paused ? "ПАУЗА" : `СКОРОСТЬ ${speed}`), [paused, speed]);

  const defaultTabs: Record<WorkspaceId, string> = {
    colonies: "overview",
    facility: "process",
    economy: "balance",
    construction: "projects",
    fleets: "ships",
    factions: "priorities",
    research: "progress",
  };
  const navigateWorkspace = (id: WorkspaceId, tab = defaultTabs[id], focus?: string) => {
    const next = { id, tab, focus };
    if (workspace && (workspace.id !== id || workspace.tab !== tab || workspace.focus !== focus)) {
      setWorkspaceHistory((history) => [...history.slice(-7), workspace]);
    }
    setWorkspace(next);
    setAlerts(false);
  };
  const goBack = () => {
    const previous = workspaceHistory.at(-1);
    if (!previous) return;
    setWorkspace(previous);
    setWorkspaceHistory((history) => history.slice(0, -1));
  };
  const closeWorkspace = () => {
    setWorkspace(null);
    setWorkspaceHistory([]);
  };
  const selectAndInspect = (next: Selection) => {
    setSelection(next);
    setAlerts(false);
  };

  return (
    <main className="app-shell">
      <TopBar
        paused={paused}
        setPaused={setPaused}
        speed={speed}
        setSpeed={setSpeed}
        openAlerts={() => setAlerts(!alerts)}
      />
      <div className="game-area">
        <SpaceMap selection={selection} onSelect={setSelection} />
        <LeftNav
          active={workspace?.id === "facility" ? null : (workspace?.id ?? null)}
          onOpen={(id) =>
            workspace?.id === id ? closeWorkspace() : navigateWorkspace(id, defaultTabs[id])
          }
        />
        <Outliner
          collapsed={outlinerCollapsed}
          setCollapsed={setOutlinerCollapsed}
          selection={selection}
          setSelection={selectAndInspect}
          openWindow={(id) => navigateWorkspace(id, defaultTabs[id])}
        />
        {selection && (
          <ContextPanel
            selection={selection}
            onClose={() => setSelection(null)}
            openWindow={navigateWorkspace}
          />
        )}
        {workspace && (
          <WorkspaceShell
            state={workspace}
            canGoBack={workspaceHistory.length > 0}
            onBack={goBack}
            onClose={closeWorkspace}
            navigate={navigateWorkspace}
            select={selectAndInspect}
          />
        )}
        {alerts && (
          <Alerts
            onClose={() => setAlerts(false)}
            investigateShortage={() => {
              setSelection("earth");
              navigateWorkspace("economy", "chains", "alloys");
            }}
            openConstruction={() => navigateWorkspace("construction", "projects", "solar")}
            followShip={() => {
              setSelection("cargo");
              navigateWorkspace("fleets", "cargo", "LS-044");
            }}
          />
        )}
        <div className={`game-status ${paused ? "paused" : ""}`}>{status}</div>
      </div>
      <footer className="statusbar">
        <span>СЕКТОР СОЛ</span>
        <i /> <span>СИСТЕМА: НОРМА</span>
        <i /> <span>СВЯЗЬ: 18 мс</span>
        <b>Наблюдение · автономная экономика</b>
      </footer>
    </main>
  );
}

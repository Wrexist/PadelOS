// PadelOS Live: the public, read-only leaderboard of one tournament.
//
// The organiser's iPhone publishes a compact JSON board to CloudKit's public database
// (record type PadelLiveBoard, record name = the random token in this page's URL
// fragment). This page reads it anonymously with CloudKit JS and refreshes every 5 s.
// No server of ours, no cookies, no analytics.
"use strict";

// ---------------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------------

// >>> The owner replaces this with the API token created in the CloudKit Console:
// >>> CloudKit Console → iCloud.app.padelos.PadelOS → Tokens & Keys → API Tokens
// >>> (see docs/RELEASE.md §3b). It only allows reading public records.
const CLOUDKIT_API_TOKEN = "a6099c6a5edf19aacaaf0ba149c23cda6694597a007a8e73d1ae15a8ef3769fb";

const CONTAINER = "iCloud.app.padelos.PadelOS";
const RECORD_TYPE = "PadelLiveBoard";
const REFRESH_MS = 5000;
// A board that is gone is checked less often.
const GONE_REFRESH_MS = 30000;
// How long to wait for CloudKit JS before saying the page cannot load.
const LOAD_TIMEOUT_MS = 15000;
const APP_LINK = "https://testflight.apple.com/join/hDXKqxBA";
const TEAM_FORMATS = new Set(["teamAmericano", "teamMexicano", "swiss"]);

// ---------------------------------------------------------------------------------
// Strings (en, es, sv)
// ---------------------------------------------------------------------------------

const STRINGS = {
  en: {
    live: "Live",
    round: "Round {x} of {y}",
    finalRound: "Final round",
    quarterfinal: "Quarterfinals",
    semifinal: "Semifinals",
    final: "Final",
    finished: "Final standings",
    courts: "Courts",
    court: "Court {n}",
    standings: "Standings",
    player: "Player",
    team: "Team",
    points: "Pts",
    games: "Games",
    record: "W-D-L",
    upNext: "Up next",
    done: "Finished",
    resting: "Resting: {names}",
    drawing: "The next round is being drawn…",
    champions: "Champions",
    runnersUp: "Runners-up: {name}",
    updatedNow: "Updated just now",
    updatedSeconds: "Updated {n} s ago",
    updatedMinutes: "Updated {n} min ago",
    updatedHours: "Updated {n} h ago",
    reconnecting: "Reconnecting…",
    fullScreen: "Full screen",
    goneTitle: "This leaderboard is not live",
    goneBody: "The organiser stopped sharing it, or the link is incomplete.",
    welcomeTitle: "Follow a padel tournament live",
    welcomeBody: "Open the link the organiser shared from PadelOS.",
    setupTitle: "Almost ready",
    setupBody: "The live leaderboard is not set up yet.",
    offlineTitle: "Can't reach the leaderboard",
    offlineBody: "Check your connection. The page keeps trying.",
    cta: "Score your own padel nights with PadelOS",
  },
  es: {
    live: "En directo",
    round: "Ronda {x} de {y}",
    finalRound: "Ronda final",
    quarterfinal: "Cuartos de final",
    semifinal: "Semifinales",
    final: "Final",
    finished: "Clasificación final",
    courts: "Pistas",
    court: "Pista {n}",
    standings: "Clasificación",
    player: "Jugador",
    team: "Equipo",
    points: "Ptos",
    games: "Juegos",
    record: "G-E-P",
    upNext: "A continuación",
    done: "Terminado",
    resting: "Descansan: {names}",
    drawing: "Se está sorteando la siguiente ronda…",
    champions: "Campeones",
    runnersUp: "Subcampeones: {name}",
    updatedNow: "Actualizado ahora mismo",
    updatedSeconds: "Actualizado hace {n} s",
    updatedMinutes: "Actualizado hace {n} min",
    updatedHours: "Actualizado hace {n} h",
    reconnecting: "Reconectando…",
    fullScreen: "Pantalla completa",
    goneTitle: "Esta clasificación no está en directo",
    goneBody: "El organizador dejó de compartirla o el enlace está incompleto.",
    welcomeTitle: "Sigue un torneo de pádel en directo",
    welcomeBody: "Abre el enlace que el organizador compartió desde PadelOS.",
    setupTitle: "Casi listo",
    setupBody: "La clasificación en directo aún no está configurada.",
    offlineTitle: "No se puede cargar la clasificación",
    offlineBody: "Comprueba tu conexión. La página lo sigue intentando.",
    cta: "Lleva el marcador de tus noches de pádel con PadelOS",
  },
  sv: {
    live: "Live",
    round: "Omgång {x} av {y}",
    finalRound: "Finalomgång",
    quarterfinal: "Kvartsfinaler",
    semifinal: "Semifinaler",
    final: "Final",
    finished: "Slutställning",
    courts: "Banor",
    court: "Bana {n}",
    standings: "Tabell",
    player: "Spelare",
    team: "Lag",
    points: "Poäng",
    games: "Gem",
    record: "V-O-F",
    upNext: "Nästa",
    done: "Klar",
    resting: "Vilar: {names}",
    drawing: "Nästa omgång lottas…",
    champions: "Vinnare",
    runnersUp: "Tvåa: {name}",
    updatedNow: "Uppdaterad nyss",
    updatedSeconds: "Uppdaterad för {n} s sedan",
    updatedMinutes: "Uppdaterad för {n} min sedan",
    updatedHours: "Uppdaterad för {n} h sedan",
    reconnecting: "Återansluter…",
    fullScreen: "Helskärm",
    goneTitle: "Den här tabellen är inte live",
    goneBody: "Arrangören har slutat dela den, eller så är länken ofullständig.",
    welcomeTitle: "Följ en padelturnering live",
    welcomeBody: "Öppna länken som arrangören delade från PadelOS.",
    setupTitle: "Nästan klart",
    setupBody: "Livetabellen är inte konfigurerad än.",
    offlineTitle: "Tabellen kan inte nås",
    offlineBody: "Kontrollera anslutningen. Sidan fortsätter att försöka.",
    cta: "Räkna poängen på dina padelkvällar med PadelOS",
  },
};

function pickLanguage() {
  const preferred = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
  for (const tag of preferred) {
    const base = String(tag).toLowerCase().split("-")[0];
    if (STRINGS[base]) return base;
  }
  return "en";
}

const LANG = pickLanguage();
document.documentElement.lang = LANG;

function t(key, values) {
  const text = (STRINGS[LANG] && STRINGS[LANG][key]) || STRINGS.en[key] || key;
  return values ? text.replace(/\{(\w+)\}/g, (_, name) => String(values[name])) : text;
}

// ---------------------------------------------------------------------------------
// DOM helpers (names are user input: always textContent, never innerHTML)
// ---------------------------------------------------------------------------------

function h(tag, attributes, ...children) {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(attributes || {})) {
    if (value === false || value === null || value === undefined) continue;
    if (name === "class") element.className = value;
    else if (name.startsWith("on")) element.addEventListener(name.slice(2), value);
    else element.setAttribute(name, value === true ? "" : value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    element.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return element;
}

const app = document.getElementById("app");

// ---------------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------------

const state = {
  token: null,
  board: null,
  updatedAt: null, // ms since epoch
  failing: false,
  previousScores: new Map(), // court number -> "a|b"
  timer: null,
  ticker: null,
};

function tokenFromLocation() {
  const raw = decodeURIComponent(location.hash.replace(/^#\/?/, "")).trim();
  return /^[0-9A-Za-z]{22,64}$/.test(raw) ? raw : null;
}

// ---------------------------------------------------------------------------------
// Data: CloudKit JS (or an injected fetcher for local previews)
// ---------------------------------------------------------------------------------

let database = null;

function configureCloudKit() {
  if (database) return database;
  window.CloudKit.configure({
    containers: [{
      containerIdentifier: CONTAINER,
      apiTokenAuth: { apiToken: CLOUDKIT_API_TOKEN, persist: false },
      environment: "production",
    }],
  });
  database = window.CloudKit.getDefaultContainer().publicCloudDatabase;
  return database;
}

function isNotFound(error) {
  return !!error && (error.ckErrorCode === "NOT_FOUND" || error.serverErrorCode === "NOT_FOUND");
}

// Resolves to { board, updatedAt } or null when the record does not exist.
async function fetchBoard(token) {
  if (typeof window.PADELOS_LIVE_FETCH === "function") return window.PADELOS_LIVE_FETCH(token);
  let response;
  try {
    response = await configureCloudKit().fetchRecords([{ recordName: token }]);
  } catch (error) {
    if (isNotFound(error)) return null;
    throw error;
  }
  if (response.hasErrors) {
    const error = response.errors[0];
    if (isNotFound(error)) return null;
    throw error;
  }
  const record = response.records && response.records[0];
  if (!record || record.recordType !== RECORD_TYPE || !record.fields || !record.fields.payload) return null;
  const board = JSON.parse(record.fields.payload.value);
  const field = record.fields.updatedAt && record.fields.updatedAt.value;
  const updatedAt = typeof field === "number" ? field : Date.parse(board.updatedAt);
  return { board, updatedAt };
}

// ---------------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------------

function renderMessage(kind, title, body) {
  stopTicker();
  app.replaceChildren(
    h("section", { class: `state state-${kind}` },
      h("div", { class: "ball", "aria-hidden": "true" }),
      h("h1", { class: "state-title" }, title),
      h("p", { class: "state-body" }, body),
      cta(),
    ),
  );
  document.title = "PadelOS Live";
}

function cta() {
  return h("a", { class: "cta", href: APP_LINK, target: "_blank", rel: "noopener" },
    h("span", { class: "cta-dot", "aria-hidden": "true" }),
    t("cta"),
    h("span", { class: "cta-arrow", "aria-hidden": "true" }, "→"),
  );
}

function roundLabel(board) {
  switch (board.stage) {
    case "final": return t("final");
    case "semifinal": return t("semifinal");
    case "quarterfinal": return t("quarterfinal");
    case "finalRound": return t("finalRound");
    default: return board.round > 0 ? t("round", { x: board.round, y: board.rounds }) : "";
  }
}

function signed(value) {
  return value > 0 ? `+${value}` : value < 0 ? `−${Math.abs(value)}` : "0";
}

function renderBoard() {
  const board = state.board;
  const finished = board.status === "completed";
  document.title = `${board.name} · PadelOS Live`;

  const header = h("header", { class: "top" },
    h("div", { class: "brand" },
      h("span", { class: "brand-ball", "aria-hidden": "true" }),
      "PadelOS",
      finished ? null : h("span", { class: "pill pill-live" }, h("span", { class: "pulse", "aria-hidden": "true" }), t("live")),
    ),
    h("h1", { class: "title" }, board.name),
    h("p", { class: "meta" },
      [board.formatName, finished ? t("finished") : roundLabel(board)].filter(Boolean).join(" · "),
    ),
  );

  const champion = board.champion ? h("section", { class: "champion" },
    h("div", { class: "trophy", "aria-hidden": "true" }, "🏆"),
    h("div", null,
      h("p", { class: "overline" }, t("champions")),
      h("p", { class: "champion-name" }, board.champion),
      board.runnerUp ? h("p", { class: "runner-up" }, t("runnersUp", { name: board.runnerUp })) : null,
    ),
  ) : null;

  const courts = finished ? null : renderCourts(board);
  const standings = renderStandings(board);

  const footer = h("footer", { class: "bottom" },
    h("div", { class: "status" },
      h("p", { class: `updated${state.failing ? " is-failing" : ""}`, id: "updated" }, updatedText()),
      document.fullscreenEnabled ? h("button", { class: "fullscreen", type: "button", onclick: toggleFullScreen }, t("fullScreen")) : null,
    ),
    cta(),
  );

  const grid = h("div", { class: `grid${courts ? "" : " grid-single"}` }, courts, standings);
  const entering = !app.querySelector(".grid");
  app.replaceChildren(...[header, champion, grid, footer].filter(Boolean));
  if (entering) {
    // Rows slide in on the first render only, not on every refresh (calm on a TV).
    app.classList.add("is-entering");
    setTimeout(() => app.classList.remove("is-entering"), 1200);
  }
  startTicker();
}

function renderCourts(board) {
  const list = board.courts || [];
  const cards = list.map((court) => renderCourt(court));
  return h("section", { class: "panel courts", "aria-label": t("courts") },
    h("h2", { class: "overline" }, t("courts")),
    list.length ? h("div", { class: "court-list" }, cards) : h("p", { class: "empty" }, t("drawing")),
    board.resting && board.resting.length ? h("p", { class: "resting" }, t("resting", { names: board.resting.join(", ") })) : null,
  );
}

function renderCourt(court) {
  const key = String(court.court);
  const scores = `${court.sa}|${court.sb}`;
  const previous = state.previousScores.get(key);
  const changed = previous !== undefined && previous !== scores;
  state.previousScores.set(key, scores);

  const numeric = /^\d+$/.test(court.sa) && /^\d+$/.test(court.sb);
  const leader = court.state !== "upcoming" && numeric && court.sa !== court.sb
    ? (Number(court.sa) > Number(court.sb) ? "a" : "b")
    : null;
  const pill = court.state === "live"
    ? h("span", { class: "pill pill-live" }, h("span", { class: "pulse", "aria-hidden": "true" }), t("live"))
    : h("span", { class: `pill pill-${court.state}` }, court.state === "finished" ? t("done") : t("upNext"));

  const side = (name, score, isLeader) => h("div", { class: `side${isLeader ? " is-leading" : ""}` },
    h("span", { class: "side-name" }, name),
    court.state === "upcoming" ? null : h("span", { class: `side-score${changed ? " bump" : ""}` }, score),
  );

  return h("article", { class: `court court-${court.state}` },
    h("div", { class: "court-head" }, h("span", { class: "overline" }, t("court", { n: court.court })), pill),
    side(court.a, court.sa, leader === "a"),
    side(court.b, court.sb, leader === "b"),
    court.sets ? h("p", { class: "sets" }, court.sets) : null,
  );
}

function renderStandings(board) {
  const rows = (board.standings || []).map((row, index) => {
    const medal = row.rank <= 3 ? ` rank-${row.rank}` : "";
    return h("tr", { class: `row${medal}`, style: `--i:${index}` },
      h("td", { class: "rank" }, h("span", { class: "rank-badge" }, `${row.tied ? "=" : ""}${row.rank}`)),
      h("td", { class: "name" }, row.name),
      h("td", { class: "num record" }, `${row.w}-${row.d}-${row.l}`),
      h("td", { class: "num diff" }, signed(row.diff)),
      h("td", { class: "num pts" }, row.pts),
    );
  });
  return h("section", { class: "panel standings", "aria-label": t("standings") },
    h("h2", { class: "overline" }, finishedOrStandings(board)),
    h("table", { class: "table" },
      h("thead", null, h("tr", null,
        h("th", { class: "rank", scope: "col" }, "#"),
        h("th", { class: "name", scope: "col" }, TEAM_FORMATS.has(board.format) ? t("team") : t("player")),
        h("th", { class: "num record", scope: "col" }, t("record")),
        h("th", { class: "num diff", scope: "col" }, "+/−"),
        h("th", { class: "num pts", scope: "col" }, board.games ? t("games") : t("points")),
      )),
      h("tbody", null, rows),
    ),
  );
}

function finishedOrStandings(board) {
  return board.status === "completed" ? t("finished") : t("standings");
}

function updatedText() {
  if (state.failing) return t("reconnecting");
  if (!state.updatedAt) return "";
  const seconds = Math.max(0, Math.round((Date.now() - state.updatedAt) / 1000));
  if (seconds < 5) return t("updatedNow");
  if (seconds < 60) return t("updatedSeconds", { n: seconds });
  if (seconds < 3600) return t("updatedMinutes", { n: Math.floor(seconds / 60) });
  return t("updatedHours", { n: Math.floor(seconds / 3600) });
}

function startTicker() {
  stopTicker();
  state.ticker = setInterval(() => {
    const element = document.getElementById("updated");
    if (!element) return;
    element.textContent = updatedText();
    element.classList.toggle("is-failing", state.failing);
  }, 1000);
}

function stopTicker() {
  if (state.ticker) clearInterval(state.ticker);
  state.ticker = null;
}

function toggleFullScreen() {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen().catch(() => {});
}

// ---------------------------------------------------------------------------------
// Refresh loop
// ---------------------------------------------------------------------------------

async function refresh() {
  clearTimeout(state.timer);
  const token = state.token;
  try {
    const result = await fetchBoard(token);
    if (token !== state.token) return; // the link changed meanwhile
    state.failing = false;
    if (!result || !result.board || typeof result.board !== "object") {
      state.board = null;
      renderMessage("gone", t("goneTitle"), t("goneBody"));
    } else {
      const changed = JSON.stringify(result.board) !== JSON.stringify(state.board);
      state.board = result.board;
      state.updatedAt = result.updatedAt || Date.parse(result.board.updatedAt) || Date.now();
      if (changed) renderBoard();
    }
  } catch (error) {
    if (token !== state.token) return;
    console.warn("PadelOS Live:", error);
    state.failing = true;
    if (!state.board) renderMessage("offline", t("offlineTitle"), t("offlineBody"));
  }
  schedule();
}

function schedule() {
  clearTimeout(state.timer);
  if (document.hidden) return; // resumes on visibilitychange
  state.timer = setTimeout(refresh, state.board || state.failing ? REFRESH_MS : GONE_REFRESH_MS);
}

function start() {
  state.token = tokenFromLocation();
  state.board = null;
  state.updatedAt = null;
  state.previousScores.clear();
  clearTimeout(state.timer);
  if (!state.token) {
    renderMessage("welcome", t("welcomeTitle"), t("welcomeBody"));
    return;
  }
  if (typeof window.PADELOS_LIVE_FETCH !== "function") {
    if (CLOUDKIT_API_TOKEN === "REPLACE_ME") {
      renderMessage("setup", t("setupTitle"), t("setupBody"));
      return;
    }
    if (!window.CloudKit) {
      // CloudKit JS is still loading (async); `cloudkitloaded` starts us again.
      state.timer = setTimeout(() => {
        if (!window.CloudKit) renderMessage("offline", t("offlineTitle"), t("offlineBody"));
      }, LOAD_TIMEOUT_MS);
      return;
    }
  }
  refresh();
}

window.addEventListener("hashchange", start);
window.addEventListener("cloudkitloaded", () => { if (state.token && !state.board) start(); });
window.addEventListener("cloudkitfailed", () => {
  if (typeof window.PADELOS_LIVE_FETCH === "function" || CLOUDKIT_API_TOKEN === "REPLACE_ME") return;
  if (state.token) renderMessage("offline", t("offlineTitle"), t("offlineBody"));
});
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && state.token && (window.CloudKit || typeof window.PADELOS_LIVE_FETCH === "function")) refresh();
});

start();

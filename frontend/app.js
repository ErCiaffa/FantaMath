const appBody = document.getElementById("app-body");

// Tutti i valori in crediti (costo, lordo, netto, plus/minus, ecc.) si mostrano interi,
// arrotondati per eccesso (2026-08-05, richiesta esplicita del proprietario).
function fmtCredit(v) {
  return v === null || v === undefined || Number.isNaN(Number(v)) ? "—" : String(Math.ceil(Number(v)));
}

const ICON_PATHS = {
  grid: '<rect width="7" height="7" x="3" y="3" rx="1.3"/><rect width="7" height="7" x="14" y="3" rx="1.3"/><rect width="7" height="7" x="14" y="14" rx="1.3"/><rect width="7" height="7" x="3" y="14" rx="1.3"/>',
  list: '<line x1="8" x2="21" y1="6" y2="6"/><line x1="8" x2="21" y1="12" y2="12"/><line x1="8" x2="21" y1="18" y2="18"/><line x1="3" x2="3.01" y1="6" y2="6"/><line x1="3" x2="3.01" y1="12" y2="12"/><line x1="3" x2="3.01" y1="18" y2="18"/>',
  users: '<path d="M17 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  calendar: '<rect width="18" height="18" x="3" y="4" rx="2"/><line x1="16" x2="16" y1="2" y2="6"/><line x1="8" x2="8" y1="2" y2="6"/><line x1="3" x2="21" y1="10" y2="10"/>',
  percent: '<line x1="19" x2="5" y1="5" y2="19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/>',
  pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
};

function icon(name, size = 15) {
  return `<svg class="icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON_PATHS[name]}</svg>`;
}

document.addEventListener("click", (event) => {
  const existing = document.querySelector(".tip-popup");
  const icon = event.target.closest(".tip-icon");
  if (existing) existing.remove();
  if (icon && icon !== existing?.dataset?.forIcon) {
    const rect = icon.getBoundingClientRect();
    const popup = document.createElement("div");
    popup.className = "tip-popup";
    popup.textContent = icon.dataset.tip;
    document.body.appendChild(popup);
    const top = Math.min(rect.bottom + 6, window.innerHeight - popup.offsetHeight - 10);
    const left = Math.min(rect.left, window.innerWidth - popup.offsetWidth - 10);
    popup.style.top = `${Math.max(top, 10)}px`;
    popup.style.left = `${Math.max(left, 10)}px`;
    event.stopPropagation();
  }
});

async function fetchState() {
  for (let attempt = 0; attempt < 3; attempt++) {
    const response = await fetch("/api/state");
    if (response.ok) {
      try {
        return await response.json();
      } catch (err) {
        // lega.json caught mid-write (rare race despite atomic rename, e.g. OneDrive sync
        // touching the file) -- retry briefly instead of surfacing a blank/stuck page.
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 300));
  }
  throw new Error("Impossibile leggere lo stato della lega dopo piu' tentativi.");
}

async function postAction(type, payload) {
  const response = await fetch("/api/actions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ type, payload }),
  });
  const { id } = await response.json();
  return pollAction(id);
}

async function pollAction(id) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const response = await fetch(`/api/actions/${id}`);
    const entry = await response.json();
    if (entry.status === "applied") return entry;
    if (entry.status === "failed") throw new Error(entry.error || "Azione fallita.");
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error("Timeout in attesa che MATLAB applicasse l'azione. Assicurati che watchLeague.m sia in esecuzione.");
}

function isOverrideSet(bankOverride) {
  return typeof bankOverride === "number" && !Number.isNaN(bankOverride);
}

function parseCsvTeams(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return [];
  const header = lines[0].split(";").map((h) => h.trim().toLowerCase());
  const teamCol = header.indexOf("fantasquadra");
  if (teamCol === -1) return [];
  const teams = new Set();
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(";");
    const team = (cols[teamCol] || "").trim();
    if (team.length > 0) teams.add(team);
  }
  return Array.from(teams);
}

function openModal({ title, fields, onSubmit }) {
  const overlay = document.createElement("div");
  overlay.className = "modal-overlay";
  overlay.innerHTML = `
    <div class="modal-box">
      <h2>${title}</h2>
      ${fields
        .map(
          (f) => `
        <div class="field">
          <label>${f.label}</label>
          <input class="input mono" id="modal-${f.key}" ${f.value !== undefined ? `value="${f.value}"` : ""} />
        </div>`
        )
        .join("")}
      <p class="sub modal-error" id="modal-error" style="display:none;"></p>
      <div class="footer-actions" style="justify-content:flex-end; display:flex; gap:10px; margin-top:14px;">
        <button class="btn btn-ghost" id="modal-cancel">Annulla</button>
        <button class="btn btn-primary" id="modal-submit">Conferma</button>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);

  const close = () => overlay.remove();
  overlay.querySelector("#modal-cancel").addEventListener("click", close);
  overlay.querySelector("#modal-submit").addEventListener("click", async () => {
    const values = {};
    for (const f of fields) {
      values[f.key] = overlay.querySelector(`#modal-${f.key}`).value;
    }
    const errorEl = overlay.querySelector("#modal-error");
    try {
      await onSubmit(values);
      close();
    } catch (err) {
      errorEl.textContent = err.message;
      errorEl.style.display = "block";
    }
  });
}

function renderError(message) {
  const box = document.createElement("p");
  box.className = "sub";
  box.style.color = "var(--danger)";
  box.textContent = message;
  appBody.prepend(box);
}

function renderNewLeagueScreen(csvPath, teamNames) {
  appBody.innerHTML = `
    <div>
      <h1>Configura la tua lega</h1>
      <p class="sub">${teamNames.length} squadre rilevate nel CSV caricato.</p>
    </div>
    <div class="panel">
      <div class="panel-head"><h2>Parametro di lega</h2></div>
      <div class="field-row">
        <div class="field" style="max-width:260px;">
          <label for="eps">Epsilon</label>
          <input class="input mono" id="eps" value="0.05" />
        </div>
      </div>
    </div>
    <div class="panel">
      <div class="panel-head"><h2>Crediti iniziali per squadra</h2></div>
      <div class="table-wrap"><table>
        <thead><tr><th>Squadra</th><th class="num">Crediti iniziali</th></tr></thead>
        <tbody>${teamNames
          .map((name) => `<tr><td>${name}</td><td class="num"><input class="cell-input mono" data-team="${name}" value="500" /></td></tr>`)
          .join("")}</tbody>
      </table></div>
    </div>
    <div class="footer-bar">
      <div></div>
      <div class="footer-actions"><button class="btn btn-primary" id="confirm-btn">Conferma e crea lega →</button></div>
    </div>
  `;

  document.getElementById("confirm-btn").addEventListener("click", async () => {
    const epsilon = parseFloat(document.getElementById("eps").value);
    const credits = teamNames.map((name) => ({
      teamName: name,
      value: parseFloat(document.querySelector(`[data-team="${CSS.escape(name)}"]`).value),
    }));
    try {
      await postAction("createLeague", { csvPath, epsilon, credits });
      await loadAndRender();
    } catch (err) {
      renderError(`Errore: ${err.message}`);
    }
  });
}

function renderUploadScreen() {
  appBody.innerHTML = `
    <div>
      <h1>Configura la tua lega</h1>
      <p class="sub">Nessuna lega salvata trovata. Carica il listone per iniziare.</p>
    </div>
    <div class="panel">
      <div class="dropzone">
        <div class="icon">CSV</div>
        <div class="title">Trascina qui il listone, o scegli un file</div>
        <input type="file" id="csv-input" accept=".csv" style="margin-top:8px;" />
      </div>
    </div>
  `;

  document.getElementById("csv-input").addEventListener("change", async (event) => {
    const file = event.target.files[0];
    if (!file) return;
    const text = await file.text();
    const teamNames = parseCsvTeams(text);

    const formData = new FormData();
    formData.append("file", file);
    const uploadResponse = await fetch("/api/upload-csv", { method: "POST", body: formData });
    const { path } = await uploadResponse.json();

    renderNewLeagueScreen(path, teamNames);
  });
}

function renderDashboard(state) {
  const teams = state.teams.table;
  const totalBanca = teams.reduce((sum, t) => sum + (isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali), 0);
  const totalBonusMalus = teams.reduce((sum, t) => sum + t.bonusMalusSum, 0);
  const totalResiduo = teams.reduce((sum, t) => sum + t.residuo, 0);
  const totalGenerale = Math.ceil(teams.reduce((sum, t) => sum + t.totale, 0));

  appBody.innerHTML = `
    <div class="toolbar">
      <div class="left">
        <h1 style="font-size:22px;">Dashboard</h1>
      </div>
      <div class="right">
        <button class="btn btn-ghost btn-sm" id="update-csv-btn">${icon("refresh", 14)}Carica nuovo CSV (aggiorna)</button>
      </div>
    </div>
    <div class="stat-grid">
      <div class="stat"><span class="k">Squadre</span><span class="v">${teams.length}</span></div>
      <div class="stat"><span class="k">Epsilon</span><span class="v gold">${state.epsilon} <span class="edit-icon" id="edit-epsilon-btn" style="vertical-align:middle;">${icon("pencil", 12)}</span></span></div>
      <div class="stat"><span class="k">Banca totale</span><span class="v">${totalBanca}</span></div>
      <div class="stat"><span class="k">Bonus/Malus totale</span><span class="v ${totalBonusMalus >= 0 ? "accent" : "gold"}">${totalBonusMalus}</span></div>
      <div class="stat"><span class="k">Residuo totale</span><span class="v accent">${totalResiduo}</span></div>
      <div class="stat"><span class="k">Totale generale</span><span class="v gold">${totalGenerale}</span></div>
    </div>
    <div class="panel" style="padding:0; overflow:hidden;">
      <div class="table-wrap" style="border:none; border-radius:0;"><table>
        <thead><tr>
          <th>Squadra</th>
          <th class="num">Banca</th>
          <th class="num">Bonus/Malus</th>
          <th class="num">Valore squadra</th>
          <th class="num">Residuo</th>
          <th class="num">Totale</th>
        </tr></thead>
        <tbody>${teams
          .map((t) => {
            const banca = isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali;
            return `<tr>
              <td class="team-name"><button class="btn-link" data-team-detail="${t.name}">${t.name}</button></td>
              <td class="num">
                <div class="bank-cell" style="justify-content:flex-end;">
                  <span class="bank-value ${banca >= 0 ? "pos" : "neg"}">${banca}</span>
                  <span class="edit-icon" data-edit-banca-for="${t.name}">${icon("pencil", 12)}</span>
                </div>
              </td>
              <td class="num">
                <div class="bank-cell" style="justify-content:flex-end;">
                  <span class="bank-value ${t.bonusMalusSum >= 0 ? "pos" : "neg"}">${t.bonusMalusSum}</span>
                  <span class="edit-icon" data-edit-bm-for="${t.name}">${icon("pencil", 12)}</span>
                </div>
              </td>
              <td class="num mono">${Math.ceil(t.teamValue)}</td>
              <td class="num mono">${t.residuo}</td>
              <td class="num mono" style="font-weight:700;">${Math.ceil(t.totale)}</td>
            </tr>`;
          })
          .join("")}</tbody>
      </table></div>
    </div>
  `;

  teams.forEach((t) => {
    document.querySelector(`[data-team-detail="${CSS.escape(t.name)}"]`).addEventListener("click", () => {
      renderTeamPanel(state, t.name);
    });
    document.querySelector(`[data-edit-banca-for="${CSS.escape(t.name)}"]`).addEventListener("click", () => {
      const currentBanca = isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali;
      openModal({
        title: `Modifica banca — ${t.name}`,
        fields: [{ key: "value", label: "Banca", value: currentBanca }],
        onSubmit: async ({ value }) => {
          const numeric = parseFloat(value);
          if (Number.isNaN(numeric)) throw new Error("Inserisci un numero valido.");
          await postAction("setBankOverride", { teamName: t.name, value: numeric });
          await loadAndRender();
        },
      });
    });
    document.querySelector(`[data-edit-bm-for="${CSS.escape(t.name)}"]`).addEventListener("click", () => {
      openModal({
        title: `Aggiungi Bonus/Malus — ${t.name}`,
        fields: [
          { key: "amount", label: "Importo (positivo=bonus, negativo=malus)", value: "" },
          { key: "motivo", label: "Motivo (obbligatorio)", value: "" },
        ],
        onSubmit: async ({ amount, motivo }) => {
          const numeric = parseFloat(amount);
          if (Number.isNaN(numeric)) throw new Error("Inserisci un importo valido.");
          if (!motivo || motivo.trim().length === 0) throw new Error("Il motivo e' obbligatorio.");
          await postAction("applyBonusMalus", { teamName: t.name, amount: numeric, motivo });
          await loadAndRender();
        },
      });
    });
  });

  document.getElementById("update-csv-btn").addEventListener("click", () => {
    renderUploadForUpdate(teams.map((t) => t.name));
  });

  document.getElementById("edit-epsilon-btn").addEventListener("click", () => {
    openModal({
      title: "Modifica Epsilon",
      fields: [{ key: "epsilon", label: "Epsilon", value: state.epsilon }],
      onSubmit: async ({ epsilon }) => {
        const numeric = parseFloat(epsilon);
        if (Number.isNaN(numeric)) throw new Error("Inserisci un numero valido.");
        await postAction("setEpsilon", { epsilon: numeric });
        await loadAndRender();
      },
    });
  });
}

function renderUploadForUpdate(knownTeamNames) {
  appBody.innerHTML = `
    <div>
      <h1>Carica nuovo listone</h1>
    </div>
    <div class="panel">
      <div class="dropzone">
        <div class="icon">CSV</div>
        <div class="title">Scegli il file CSV aggiornato</div>
        <input type="file" id="csv-input" accept=".csv" style="margin-top:8px;" />
      </div>
    </div>
    <div id="update-extra"></div>
    <p class="sub" id="update-status"></p>
  `;

  document.getElementById("csv-input").addEventListener("change", async (event) => {
    const file = event.target.files[0];
    if (!file) return;
    const statusEl = document.getElementById("update-status");
    statusEl.textContent = "Caricamento in corso…";

    const text = await file.text();
    const csvTeamNames = parseCsvTeams(text);
    const newTeamNames = csvTeamNames.filter((name) => !knownTeamNames.includes(name));

    const formData = new FormData();
    formData.append("file", file);
    const uploadResponse = await fetch("/api/upload-csv", { method: "POST", body: formData });
    const { path } = await uploadResponse.json();

    if (newTeamNames.length === 0) {
      await submitMerge(path, [], statusEl);
      return;
    }

    statusEl.textContent = `${newTeamNames.length} nuova/e squadra/e rilevata/e: imposta i crediti iniziali prima di confermare.`;
    const extra = document.getElementById("update-extra");
    extra.innerHTML = `
      <div class="panel">
        <div class="panel-head"><h2>Crediti iniziali — squadre nuove</h2></div>
        <div class="table-wrap"><table>
          <thead><tr><th>Squadra</th><th class="num">Crediti iniziali</th></tr></thead>
          <tbody>${newTeamNames
            .map((name) => `<tr><td>${name}</td><td class="num"><input class="cell-input mono" data-newteam="${name}" value="500" /></td></tr>`)
            .join("")}</tbody>
        </table></div>
      </div>
      <div class="footer-bar">
        <div></div>
        <div class="footer-actions"><button class="btn btn-primary" id="confirm-merge-btn">Conferma aggiornamento →</button></div>
      </div>
    `;
    document.getElementById("confirm-merge-btn").addEventListener("click", async () => {
      const newTeamCredits = newTeamNames.map((name) => ({
        teamName: name,
        value: parseFloat(document.querySelector(`[data-newteam="${CSS.escape(name)}"]`).value),
      }));
      await submitMerge(path, newTeamCredits, statusEl);
    });
  });
}

async function submitMerge(csvPath, newTeamCredits, statusEl) {
  try {
    statusEl.textContent = "MATLAB sta applicando l'aggiornamento…";
    await postAction("mergeCsv", { csvPath, newTeamCredits });
    await loadAndRender();
  } catch (err) {
    statusEl.textContent = `Errore: ${err.message}`;
  }
}

function computeStats(values) {
  const n = values.length;
  if (n === 0) return { mean: 0, std: 0, skewness: 0, median: 0 };
  const mean = values.reduce((s, v) => s + v, 0) / n;
  const variance = values.reduce((s, v) => s + (v - mean) ** 2, 0) / n;
  const std = Math.sqrt(variance);
  const skewness = std > 0 ? values.reduce((s, v) => s + ((v - mean) / std) ** 3, 0) / n : 0;
  const sorted = [...values].sort((a, b) => a - b);
  const median = n % 2 === 0 ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[(n - 1) / 2];
  return { mean, std, skewness, median };
}

function skewnessLabel(skewness) {
  const abs = Math.abs(skewness);
  if (abs < 0.5) return "vicina a una normale (poco asimmetrica)";
  if (abs < 1) return "moderatamente asimmetrica";
  return "molto asimmetrica" + (skewness > 0 ? " (coda a destra: molti bassi, pochi alti)" : " (coda a sinistra: molti alti, pochi bassi)");
}

function drawHistogram(canvas, values, opts) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const styles = getComputedStyle(document.documentElement);
  const gridColor = styles.getPropertyValue("--line-soft").trim() || "#333";
  const barColor = opts.color || styles.getPropertyValue("--accent").trim() || "#4c9a6a";
  const textColor = styles.getPropertyValue("--text-faint").trim() || "#888";
  const lineColor = styles.getPropertyValue("--chart-line").trim() || "#ffffff90";

  const nBins = opts.bins || 24;
  const min = opts.min !== undefined ? opts.min : Math.min(...values);
  const max = opts.max !== undefined ? opts.max : Math.max(...values);
  const span = max - min || 1;
  const binWidth = span / nBins;
  const counts = new Array(nBins).fill(0);
  for (const v of values) {
    let idx = Math.floor(((v - min) / span) * nBins);
    if (idx < 0) idx = 0;
    if (idx >= nBins) idx = nBins - 1;
    counts[idx]++;
  }
  const stats = computeStats(values);

  const padLeft = 30;
  const padBottom = 30;
  const padTop = 10;
  const padRight = 6;
  const plotW = w - padLeft - padRight;
  const plotH = h - padBottom - padTop;
  const maxCount = Math.max(...counts, 1);
  const barW = plotW / nBins;

  // axes
  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padLeft, padTop);
  ctx.lineTo(padLeft, h - padBottom);
  ctx.lineTo(w - padRight, h - padBottom);
  ctx.stroke();

  // y ticks: 0 and max
  ctx.fillStyle = textColor;
  ctx.font = "9px ui-monospace, monospace";
  ctx.textAlign = "right";
  ctx.fillText("0", padLeft - 4, h - padBottom);
  ctx.fillText(String(maxCount), padLeft - 4, padTop + 8);

  // bars
  ctx.fillStyle = barColor;
  counts.forEach((c, i) => {
    const barH = (c / maxCount) * plotH;
    ctx.fillRect(padLeft + i * barW + 1, h - padBottom - barH, Math.max(barW - 2, 1), barH);
  });

  // normal curve overlay, same count-scale as the bars
  if (opts.showNormal && stats.std > 0) {
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 2;
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    for (let px = 0; px <= plotW; px++) {
      const x = min + (px / plotW) * span;
      const pdf = Math.exp(-0.5 * ((x - stats.mean) / stats.std) ** 2) / (stats.std * Math.sqrt(2 * Math.PI));
      const expectedCount = pdf * values.length * binWidth;
      const y = h - padBottom - (expectedCount / maxCount) * plotH;
      if (px === 0) ctx.moveTo(padLeft + px, y);
      else ctx.lineTo(padLeft + px, y);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // x ticks
  ctx.fillStyle = textColor;
  ctx.textAlign = "left";
  ctx.fillText(min.toFixed(2), padLeft, h - padBottom + 12);
  ctx.textAlign = "right";
  ctx.fillText(max.toFixed(2), w - padRight, h - padBottom + 12);

  // axis titles
  ctx.textAlign = "center";
  ctx.fillText(opts.xLabel || "Punteggio (0-1)", padLeft + plotW / 2, h - 2);
  ctx.save();
  ctx.translate(9, padTop + plotH / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText(opts.yLabel || "N. giocatori", 0, 0);
  ctx.restore();

  return stats;
}

function drawLineSeries(canvas, series, opts) {
  // series: [{ label, color, points: [{x, y}, ...] }, ...]
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const styles = getComputedStyle(document.documentElement);
  const gridColor = styles.getPropertyValue("--line-soft").trim() || "#333";
  const textColor = styles.getPropertyValue("--text-faint").trim() || "#888";

  const allX = series.flatMap((s) => s.points.map((p) => p.x));
  const allY = series.flatMap((s) => s.points.map((p) => p.y));
  const minX = opts.minX !== undefined ? opts.minX : Math.min(...allX);
  const maxX = opts.maxX !== undefined ? opts.maxX : Math.max(...allX);
  const minY = 0;
  const maxY = opts.maxY !== undefined ? opts.maxY : Math.max(...allY, 1) * 1.08;

  const padLeft = 34;
  const padBottom = 26;
  const padTop = 14;
  const padRight = 8;
  const plotW = w - padLeft - padRight;
  const plotH = h - padBottom - padTop;

  const xToPx = (x) => padLeft + ((x - minX) / (maxX - minX || 1)) * plotW;
  const yToPx = (y) => h - padBottom - ((y - minY) / (maxY - minY || 1)) * plotH;

  // gridlines (horizontal, 4 steps)
  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const y = padTop + (plotH / 4) * i;
    ctx.beginPath();
    ctx.moveTo(padLeft, y);
    ctx.lineTo(w - padRight, y);
    ctx.stroke();
  }

  // axes
  ctx.strokeStyle = textColor;
  ctx.beginPath();
  ctx.moveTo(padLeft, padTop);
  ctx.lineTo(padLeft, h - padBottom);
  ctx.lineTo(w - padRight, h - padBottom);
  ctx.stroke();

  // vertical threshold markers
  if (opts.markers) {
    ctx.setLineDash([4, 3]);
    ctx.strokeStyle = styles.getPropertyValue("--gold").trim() || "#d9a94e";
    for (const m of opts.markers) {
      const x = xToPx(m.x);
      ctx.beginPath();
      ctx.moveTo(x, padTop);
      ctx.lineTo(x, h - padBottom);
      ctx.stroke();
      ctx.fillStyle = ctx.strokeStyle;
      ctx.font = "9px ui-monospace, monospace";
      ctx.textAlign = "center";
      ctx.fillText(m.label, x, padTop - 3);
    }
    ctx.setLineDash([]);
  }

  // y ticks
  ctx.fillStyle = textColor;
  ctx.font = "9px ui-monospace, monospace";
  ctx.textAlign = "right";
  ctx.fillText("0", padLeft - 5, h - padBottom + 3);
  ctx.fillText(maxY.toFixed(0), padLeft - 5, padTop + 8);

  // x ticks (min/max)
  ctx.textAlign = "left";
  ctx.fillText(String(minX), padLeft, h - padBottom + 14);
  ctx.textAlign = "right";
  ctx.fillText(String(maxX), w - padRight, h - padBottom + 14);

  // series lines + markers
  for (const s of series) {
    const pts = s.points.slice().sort((a, b) => a.x - b.x);
    ctx.strokeStyle = s.color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    pts.forEach((p, i) => {
      const px = xToPx(p.x);
      const py = yToPx(p.y);
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    });
    ctx.stroke();
    ctx.fillStyle = s.color;
    pts.forEach((p) => {
      ctx.beginPath();
      ctx.arc(xToPx(p.x), yToPx(p.y), 2, 0, Math.PI * 2);
      ctx.fill();
    });
  }

  // axis titles
  ctx.fillStyle = textColor;
  ctx.textAlign = "center";
  ctx.fillText(opts.xLabel || "", padLeft + plotW / 2, h - 2);
  ctx.save();
  ctx.translate(9, padTop + plotH / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText(opts.yLabel || "", 0, 0);
  ctx.restore();
}

function drawBarChart(canvas, categories, values, opts = {}) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const styles = getComputedStyle(document.documentElement);
  const gridColor = styles.getPropertyValue("--line-soft").trim() || "#333";
  const barColor = opts.color || styles.getPropertyValue("--accent").trim();
  const textColor = styles.getPropertyValue("--text-faint").trim() || "#888";
  const valueColor = styles.getPropertyValue("--text-hi").trim() || "#fff";

  const padLeft = 26;
  const padBottom = 22;
  const padTop = 16;
  const padRight = 6;
  const plotW = w - padLeft - padRight;
  const plotH = h - padBottom - padTop;
  const maxV = Math.max(...values, 1);
  const barW = plotW / categories.length;

  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padLeft, padTop);
  ctx.lineTo(padLeft, h - padBottom);
  ctx.lineTo(w - padRight, h - padBottom);
  ctx.stroke();

  ctx.fillStyle = barColor;
  values.forEach((v, i) => {
    const barH = (v / maxV) * plotH;
    ctx.fillRect(padLeft + i * barW + 2, h - padBottom - barH, Math.max(barW - 4, 1), barH);
  });

  ctx.font = "9.5px ui-monospace, monospace";
  ctx.fillStyle = valueColor;
  ctx.textAlign = "center";
  values.forEach((v, i) => {
    const barH = (v / maxV) * plotH;
    ctx.fillText(String(v), padLeft + i * barW + barW / 2, h - padBottom - barH - 4);
  });

  ctx.fillStyle = textColor;
  categories.forEach((c, i) => {
    ctx.fillText(c, padLeft + i * barW + barW / 2, h - padBottom + 12);
  });
}

function drawRadar(canvas, categories, series, opts = {}) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const styles = getComputedStyle(document.documentElement);
  const gridColor = styles.getPropertyValue("--line-soft").trim() || "#333";
  const textColor = styles.getPropertyValue("--text-faint").trim() || "#888";

  const n = categories.length;
  const cx = w / 2;
  const cy = h / 2 + 4;
  const radius = Math.min(w, h) / 2 - 30;
  const maxV = opts.max !== undefined ? opts.max : Math.max(...series.flatMap((s) => s.values), 1);
  const angleFor = (i) => -Math.PI / 2 + (i / n) * Math.PI * 2;
  const pointFor = (i, v) => {
    const r = (Math.max(v, 0) / maxV) * radius;
    const a = angleFor(i);
    return { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) };
  };

  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 1;
  [0.25, 0.5, 0.75, 1].forEach((frac) => {
    ctx.beginPath();
    for (let i = 0; i <= n; i++) {
      const a = angleFor(i % n);
      const r = frac * radius;
      const x = cx + r * Math.cos(a);
      const y = cy + r * Math.sin(a);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  });

  ctx.fillStyle = textColor;
  ctx.font = "10px ui-monospace, monospace";
  ctx.textAlign = "center";
  for (let i = 0; i < n; i++) {
    const a = angleFor(i);
    const x2 = cx + radius * Math.cos(a);
    const y2 = cy + radius * Math.sin(a);
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(x2, y2);
    ctx.stroke();
    const lx = cx + (radius + 14) * Math.cos(a);
    const ly = cy + (radius + 14) * Math.sin(a) + 3;
    ctx.fillText(categories[i], lx, ly);
  }

  series.forEach((s) => {
    ctx.beginPath();
    s.values.forEach((v, i) => {
      const p = pointFor(i, v);
      if (i === 0) ctx.moveTo(p.x, p.y);
      else ctx.lineTo(p.x, p.y);
    });
    ctx.closePath();
    ctx.fillStyle = s.fill || `${s.color}26`;
    ctx.fill();
    ctx.setLineDash(s.dashed ? [4, 3] : []);
    ctx.strokeStyle = s.color;
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = s.color;
    s.values.forEach((v, i) => {
      const p = pointFor(i, v);
      ctx.beginPath();
      ctx.arc(p.x, p.y, 2.2, 0, Math.PI * 2);
      ctx.fill();
    });
  });
}

function renderAgePanel(state) {
  renderNavbar("age", true);
  const p = state.params;
  const byAge = new Map();
  for (const player of state.players) {
    if (player.fuoriLista) continue;
    const age = player.age;
    if (age === null || age === undefined || Number.isNaN(age)) continue;
    const a = Math.round(age);
    if (!byAge.has(a)) byAge.set(a, { owned: [], free: [] });
    (player.owned ? byAge.get(a).owned : byAge.get(a).free).push(player.fvm);
  }
  const ages = [...byAge.keys()].sort((x, y) => x - y);
  const avg = (arr) => (arr.length ? arr.reduce((s, v) => s + v, 0) / arr.length : 0);
  const rows = ages.map((a) => {
    const b = byAge.get(a);
    return { age: a, nOwned: b.owned.length, nFree: b.free.length, fvmOwned: avg(b.owned), fvmFree: avg(b.free) };
  });

  const styles = getComputedStyle(document.documentElement);

  appBody.innerHTML = `
    <div>
      <h1>Peso Età</h1>
      <p class="sub">Termine additivo per il valore finale: bonus per i giovani (margine di crescita in una lega pluriennale), rampa lineare che scende gradualmente a 0 — niente malus, mai negativo. Parametri modificabili, non applicati se non salvi.</p>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>FVM medio per eta'</h2>
        <span class="hint">Serie posseduti (verde) / liberi (blu) — linee gialle = soglie attuali</span></div>
      <div class="legend-row sub">
        <span><i class="dot" style="background:var(--accent);"></i> Posseduti</span>
        <span><i class="dot" style="background:var(--chart-blue);"></i> Liberi</span>
      </div>
      <canvas id="age-chart" width="960" height="220" style="width:100%; height:220px;"></canvas>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Parametri</h2>
        <span class="hint">Rampa lineare: bonus massimo a etaFloor, scende a 0 a etaZero, mai negativo (niente malus veterani)</span></div>
      <div class="field-row">
        <div class="field">
          <label for="eta-floor">etaFloor (eta' minima Serie A, bonus massimo qui e sotto)</label>
          <input class="input mono" id="eta-floor" value="${p.etaFloor}" />
        </div>
        <div class="field">
          <label for="eta-zero">etaZero (eta' a cui il bonus arriva a 0)</label>
          <input class="input mono" id="eta-zero" value="${p.etaZero}" />
        </div>
      </div>
      <div class="field-row">
        <div class="field">
          <label for="eta-bonus-max">Bonus massimo a etaFloor (0-1, es. 0.10 = 10%)</label>
          <input class="input mono" id="eta-bonus-max" value="${p.etaBonusMax}" />
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Tabella per eta'</h2></div>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Eta'</th><th>Poss.</th><th>Liberi</th><th>FVM poss.</th><th>FVM liberi</th></tr></thead>
          <tbody>
            ${rows.map((r) => `
              <tr>
                <td class="mono">${r.age}</td>
                <td class="mono sub">${r.nOwned}</td>
                <td class="mono sub">${r.nFree}</td>
                <td class="mono sub">${r.fvmOwned.toFixed(1)}</td>
                <td class="mono sub">${r.fvmFree.toFixed(1)}</td>
              </tr>`).join("")}
          </tbody>
        </table>
      </div>
    </div>

    <div class="footer-bar">
      <div></div>
      <div class="footer-actions">
        <button class="btn btn-ghost" id="age-back-btn">← Torna alla dashboard</button>
        <button class="btn btn-primary" id="age-apply-btn">Salva</button>
      </div>
    </div>
    <p class="sub" id="age-status"></p>
  `;

  drawLineSeries(document.getElementById("age-chart"), [
    { label: "Posseduti", color: styles.getPropertyValue("--accent").trim(), points: rows.map((r) => ({ x: r.age, y: r.fvmOwned })) },
    { label: "Liberi", color: styles.getPropertyValue("--chart-blue").trim(), points: rows.map((r) => ({ x: r.age, y: r.fvmFree })) },
  ], {
    xLabel: "Eta'",
    yLabel: "FVM medio",
    markers: [
      { x: p.etaFloor, label: `≤${p.etaFloor} bonus max` },
      { x: p.etaZero, label: `≥${p.etaZero} bonus 0` },
    ],
  });

  document.getElementById("age-back-btn").addEventListener("click", () => loadAndRender());

  document.getElementById("age-apply-btn").addEventListener("click", async () => {
    const statusEl = document.getElementById("age-status");
    const etaFloor = parseFloat(document.getElementById("eta-floor").value);
    const etaZero = parseFloat(document.getElementById("eta-zero").value);
    const etaBonusMax = parseFloat(document.getElementById("eta-bonus-max").value);
    if ([etaFloor, etaZero, etaBonusMax].some((v) => Number.isNaN(v))) {
      statusEl.textContent = "Errore: valori non validi.";
      return;
    }
    if (etaFloor >= etaZero) {
      statusEl.textContent = "Errore: etaFloor deve essere minore di etaZero.";
      return;
    }
    statusEl.textContent = "MATLAB sta ricalcolando i punteggi…";
    try {
      await postAction("setEtaParams", { etaFloor, etaZero, etaBonusMax });
      const newState = await fetchState();
      renderAgePanel(newState);
    } catch (err) {
      statusEl.textContent = `Errore: ${err.message}`;
    }
  });
}

function renderTaxPanel(state) {
  renderNavbar("tax", true);
  const p = state.params;
  const scoresById = new Map(state.scores.map((s) => [s.id, s]));
  const rows = state.players
    .filter((pl) => pl.owned)
    .map((pl) => {
      const s = scoresById.get(pl.id) || {};
      return {
        nome: pl.nome, costo: pl.costo || 0,
        lordo: s.creditoStimato || 0, netto: s.incassoNettoDecisionale || 0,
      };
    })
    .sort((a, b) => b.lordo - a.lordo);
  const lordoTot = rows.reduce((s, r) => s + r.lordo, 0);
  const nettoTot = rows.reduce((s, r) => s + r.netto, 0);
  const calo = lordoTot > 0 ? (1 - nettoTot / lordoTot) * 100 : 0;

  appBody.innerHTML = `
    <div>
      <h1>Tasse svincolo</h1>
      <p class="sub">Tassa sul valore (motivo estero/decisionale) + tassa plusvalenza + recupero minusvalenza. Anteprima "netto" qui sotto assume sempre svincolo decisionale (motivo più comune) sul costo pagato realmente.</p>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Parametri</h2></div>
      <div class="field-row">
        <div class="field"><label for="tax-estero">Estero (0-1)</label><input class="input mono" id="tax-estero" value="${p.taxEstero}" /></div>
        <div class="field"><label for="tax-decisionale">Decisionale (0-1)</label><input class="input mono" id="tax-decisionale" value="${p.taxDecisionale}" /></div>
      </div>
      <div class="field-row">
        <div class="field"><label for="tax-plus">Plusvalenza (0-1)</label><input class="input mono" id="tax-plus" value="${p.taxPlusvalenza}" /></div>
        <div class="field"><label for="tax-minus">Minusvalenza recupero (0-1)</label><input class="input mono" id="tax-minus" value="${p.taxMinusvalenza}" /></div>
        <div class="field"><label for="tax-fee">Fee fissa (crediti)</label><input class="input mono" id="tax-fee" value="${p.taxFee}" /></div>
      </div>
      <div class="field-row"><button class="btn btn-primary" id="tax-apply-btn">Salva</button></div>
      <p class="sub" id="tax-status"></p>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Impatto totale (se tutti svincolassero ora, decisionale)</h2></div>
      <p class="sub mono">Lordo: ${fmtCredit(lordoTot)}  →  Netto: ${fmtCredit(nettoTot)}  (calo ${calo.toFixed(1)}%)</p>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Nome</th><th>Costo</th><th>Lordo</th><th>Netto</th></tr></thead>
          <tbody>${rows.slice(0, 30).map((r) => `<tr><td>${r.nome}</td><td class="mono sub">${fmtCredit(r.costo)}</td><td class="mono sub">${fmtCredit(r.lordo)}</td><td class="mono" style="font-weight:700;">${fmtCredit(r.netto)}</td></tr>`).join("")}</tbody>
        </table>
      </div>
    </div>

    <div class="footer-bar"><div></div><div class="footer-actions"><button class="btn btn-ghost" id="tax-back-btn">← Torna alla dashboard</button></div></div>
  `;

  document.getElementById("tax-back-btn").addEventListener("click", () => loadAndRender());
  document.getElementById("tax-apply-btn").addEventListener("click", async () => {
    const statusEl = document.getElementById("tax-status");
    const taxEstero = parseFloat(document.getElementById("tax-estero").value);
    const taxDecisionale = parseFloat(document.getElementById("tax-decisionale").value);
    const taxPlusvalenza = parseFloat(document.getElementById("tax-plus").value);
    const taxMinusvalenza = parseFloat(document.getElementById("tax-minus").value);
    const taxFee = parseFloat(document.getElementById("tax-fee").value);
    if ([taxEstero, taxDecisionale, taxPlusvalenza, taxMinusvalenza, taxFee].some((v) => Number.isNaN(v))) {
      statusEl.textContent = "Errore: valori non validi.";
      return;
    }
    statusEl.textContent = "MATLAB sta ricalcolando…";
    try {
      await postAction("setTaxParams", { taxEstero, taxDecisionale, taxPlusvalenza, taxMinusvalenza, taxFee });
      renderTaxPanel(await fetchState());
    } catch (err) {
      statusEl.textContent = `Errore: ${err.message}`;
    }
  });
}

function renderFormulaPanel(state) {
  renderNavbar("formula", true);
  const p = state.params;
  const quotWeight = Math.round((1 - p.phi) * 100);

  appBody.innerHTML = `
    <div>
      <h1>Normalizzazione FVM / QUOT</h1>
      <p class="sub">FVM e QUOT vengono compressi e tagliati separatamente, poi mescolati con φ. Regola e guarda l'istogramma cambiare.</p>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Peso FVM / QUOT</h2></div>
      <div class="field">
        <label for="phi-slider">φ (peso QUOT %) <span class="edit-icon tip-icon" data-tip="Quanto pesano FVM e QUOT nel punteggio finale. Alza per dare piu' peso al QUOT (prezzo di mercato reale), abbassa per dare piu' peso al FVM (proiezione fantavoto). phi=1 -> solo FVM, phi=0 -> solo QUOT.">?</span></label>
        <input type="range" id="phi-slider" min="0" max="100" value="${quotWeight}" style="width:100%;" />
        <span class="sub mono" id="phi-value">QUOT ${quotWeight}% / FVM ${100 - quotWeight}%</span>
      </div>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Compressione logaritmica</h2></div>
      <div class="field-row">
        <div class="field">
          <label for="alphaF-input">α<sub>F</sub> (FVM) <span class="edit-icon tip-icon" data-tip="Comprime i valori FVM molto alti prima di normalizzare. Alza per appiattire di piu' le differenze tra i top player, abbassa (verso 0.0001) per comprimere pochissimo.">?</span></label>
          <input class="input mono" id="alphaF-input" value="${p.alphaF}" />
        </div>
        <div class="field">
          <label for="alphaQ-input">α<sub>Q</sub> (QUOT) <span class="edit-icon tip-icon" data-tip="Comprime i valori QUOT molto alti prima di normalizzare. Stesso principio di alpha_F ma sul prezzo di mercato.">?</span></label>
          <input class="input mono" id="alphaQ-input" value="${p.alphaQ}" />
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Taglio percentile</h2></div>
      <div class="field-row">
        <div class="field">
          <label for="pLow-input">p<sub>low</sub> <span class="edit-icon tip-icon" data-tip="Percentile basso da tagliare prima di normalizzare (0-1). Alza per ignorare i valori piu' bassi. Default 0 = nessun taglio.">?</span></label>
          <input class="input mono" id="pLow-input" value="${p.pLow}" />
        </div>
        <div class="field">
          <label for="pHigh-input">p<sub>high</sub> <span class="edit-icon tip-icon" data-tip="Percentile alto da tagliare prima di normalizzare (0-1). Abbassa per ignorare i valori piu' alti. Default 1 = nessun taglio.">?</span></label>
          <input class="input mono" id="pHigh-input" value="${p.pHigh}" />
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Distribuzione punteggi intermedi (0-1)</h2>
        <span class="hint">Separati, prima del mix con φ</span></div>
      <div class="field-row">
        <div class="field">
          <label>F_score (da FVM)</label>
          <canvas id="hist-fscore" width="480" height="160" style="width:100%; height:160px;"></canvas>
          <p class="sub mono" id="stats-fscore"></p>
        </div>
        <div class="field">
          <label>Q_score (da QUOT)</label>
          <canvas id="hist-qscore" width="480" height="160" style="width:100%; height:160px;"></canvas>
          <p class="sub mono" id="stats-qscore"></p>
        </div>
      </div>
    </div>

    <div class="panel" style="border-color:var(--gold);">
      <div class="panel-head"><h2>S — Punteggio finale (0-1)</h2>
        <span class="hint">F_score e Q_score mescolati con φ — questo diventa il valore svincolo</span></div>
      <canvas id="hist-score" width="960" height="180" style="width:100%; height:180px;"></canvas>
      <p class="sub mono" id="stats-score"></p>
    </div>

    <div class="footer-bar">
      <div></div>
      <div class="footer-actions">
        <button class="btn btn-ghost" id="formula-back-btn">← Torna alla dashboard</button>
        <button class="btn btn-primary" id="formula-apply-btn">Applica</button>
      </div>
    </div>
    <p class="sub" id="formula-status"></p>
  `;

  const fmtStats = (stats) =>
    `media ${stats.mean.toFixed(3)} · mediana ${stats.median.toFixed(3)} · dev.std ${stats.std.toFixed(3)} · ${skewnessLabel(stats.skewness)} (asimmetria ${stats.skewness.toFixed(2)})`;

  const redraw = () => {
    const styles = getComputedStyle(document.documentElement);
    const fScores = state.scores.map((s) => s.fScore);
    const qScores = state.scores.map((s) => s.qScore);
    const finalScores = state.scores.map((s) => s.score);

    const statsF = drawHistogram(document.getElementById("hist-fscore"), fScores, { min: 0, max: 1, color: styles.getPropertyValue("--accent"), xLabel: "F_score (0-1)", showNormal: true });
    const statsQ = drawHistogram(document.getElementById("hist-qscore"), qScores, { min: 0, max: 1, color: styles.getPropertyValue("--chart-blue"), xLabel: "Q_score (0-1)", showNormal: true });
    const statsS = drawHistogram(document.getElementById("hist-score"), finalScores, { min: 0, max: 1, bins: 30, color: styles.getPropertyValue("--gold"), xLabel: "S — punteggio finale (0-1)", showNormal: true });

    document.getElementById("stats-fscore").textContent = fmtStats(statsF);
    document.getElementById("stats-qscore").textContent = fmtStats(statsQ);
    document.getElementById("stats-score").textContent = fmtStats(statsS);
  };
  redraw();

  document.getElementById("phi-slider").addEventListener("input", (event) => {
    const qw = parseInt(event.target.value, 10);
    document.getElementById("phi-value").textContent = `QUOT ${qw}% / FVM ${100 - qw}%`;
  });

  document.getElementById("formula-back-btn").addEventListener("click", () => loadAndRender());

  document.getElementById("formula-apply-btn").addEventListener("click", async () => {
    const statusEl = document.getElementById("formula-status");
    const qw = parseInt(document.getElementById("phi-slider").value, 10);
    const phi = 1 - qw / 100;
    const alphaF = parseFloat(document.getElementById("alphaF-input").value);
    const alphaQ = parseFloat(document.getElementById("alphaQ-input").value);
    const pLow = parseFloat(document.getElementById("pLow-input").value);
    const pHigh = parseFloat(document.getElementById("pHigh-input").value);

    if ([alphaF, alphaQ, pLow, pHigh].some((v) => Number.isNaN(v))) {
      statusEl.textContent = "Errore: valori non validi.";
      return;
    }

    statusEl.textContent = "MATLAB sta ricalcolando i punteggi…";
    try {
      await postAction("setFormulaParams", { phi, alphaF, alphaQ, pLow, pHigh });
      const newState = await fetchState();
      renderFormulaPanel(newState);
    } catch (err) {
      statusEl.textContent = `Errore: ${err.message}`;
    }
  });
}

const ROLE_LABELS = {
  Por: "Portiere",
  Dc: "Difensore centrale",
  B: "Braccetto",
  Ds: "Terzino sinistro",
  Dd: "Terzino destro",
  M: "Mediano",
  C: "Centrocampista centrale",
  E: "Esterno",
  W: "Ala",
  T: "Trequartista",
  Pc: "Punta centrale",
  A: "Attaccante",
};
const ROLE_ORDER = ["Por", "Dc", "B", "Ds", "Dd", "M", "C", "E", "W", "T", "Pc", "A"];

// Port 1:1 di src.engine.roleDemand (FantaManager/+src/+engine/roleDemand.m,
// buildMantraModules): gli 11 moduli tattici standard del sistema Mantra usati
// dal motore MATLAB per la domanda di ruolo. Ogni modulo ha 11 slot; uno slot con
// piu' token (es. ["Dc","B"]) ammette qualunque giocatore con quel ruolo Mantra.
// Difesa: Dc=centrale, Dd=terzino destro, Ds=terzino sinistro, B=braccetto (centrale
// nella difesa a 3). Centrocampo: M=mediano, C=centrale, E=esterno, W=ala, T=trequartista.
// Attacco: Pc=punta centrale, A=attaccante.
const MANTRA_MODULES = [
  { name: "3-4-3", slots: ["Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "C", "E", "E", ["W", "A"], ["W", "A"], ["A", "Pc"]] },
  { name: "3-4-1-2", slots: ["Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "C", "E", "E", "T", ["A", "Pc"], ["A", "Pc"]] },
  { name: "3-5-2", slots: ["Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "C", "M", "E", ["E", "W"], ["A", "Pc"], ["A", "Pc"]] },
  { name: "3-4-2-1", slots: ["Por", "Dc", "Dc", ["Dc", "B"], ["M", "C"], "M", "E", ["E", "W"], "T", ["T", "A"], ["A", "Pc"]] },
  { name: "3-5-1-1", slots: ["Por", "Dc", "Dc", ["Dc", "B"], "M", "C", "M", ["E", "W"], ["E", "W"], ["T", "A"], ["A", "Pc"]] },
  { name: "4-3-3", slots: ["Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "C", "M", ["W", "A"], ["W", "A"], ["A", "Pc"]] },
  { name: "4-3-1-2", slots: ["Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "C", "M", "T", ["T", "A", "Pc"], ["A", "Pc"]] },
  { name: "4-4-2", slots: ["Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "C", "E", ["E", "W"], ["A", "Pc"], ["A", "Pc"]] },
  { name: "4-2-3-1", slots: ["Por", "Dc", "Dc", "Ds", "Dd", ["M", "C"], "M", "T", ["W", "T"], ["W", "A"], ["A", "Pc"]] },
  { name: "4-4-1-1", slots: ["Por", "Dc", "Dc", "Ds", "Dd", "C", "M", ["E", "W"], ["E", "W"], ["T", "A"], ["A", "Pc"]] },
  { name: "4-1-4-1", slots: ["Por", "Dc", "Dc", "Ds", "Dd", "M", ["C", "T"], ["E", "W"], "T", "W", ["A", "Pc"]] },
];

// Assegna la miglior formazione titolare fattibile per un modulo Mantra: gli slot piu'
// vincolati (meno token ammessi, es. "Por" o "Dc" puro) vengono riempiti prima con
// l'euristica "most-constrained-first" (CSP classico), col giocatore di valore piu' alto
// tra quelli ancora liberi ed eleggibili per quello slot. Greedy, non garantito ottimo,
// ma ogni assegnazione resta visibile in tabella (PRODUCT.md: mai solo il risultato).
function bestXIForModule(players, mod) {
  const slots = mod.slots.map((s, i) => ({ index: i, roles: Array.isArray(s) ? s : [s] }));
  const order = [...slots].sort((a, b) => a.roles.length - b.roles.length || a.index - b.index);

  const used = new Set();
  const assigned = new Array(slots.length).fill(null);
  const missingSlots = [];

  for (const slot of order) {
    const candidates = players
      .filter((p) => !used.has(p.nome) && p.mantraRoles.some((r) => slot.roles.includes(r)))
      .sort((a, b) => b.lordo - a.lordo);
    if (candidates.length === 0) {
      missingSlots.push(slot.roles.join("/"));
      continue;
    }
    used.add(candidates[0].nome);
    assigned[slot.index] = candidates[0];
  }

  const starters = assigned.filter(Boolean);
  const totalValue = starters.reduce((s, p) => s + p.lordo, 0);
  const bench = players.filter((p) => !used.has(p.nome));
  const relevantRoles = [...new Set(slots.flatMap((s) => s.roles))];

  return { formation: mod.name, feasible: missingSlots.length === 0, missingSlots, slots, assigned, totalValue, bench, relevantRoles };
}

function roleBarRow(label, value, max, color, valueLabel) {
  const pct = value <= 0 ? 0 : Math.max(2, (value / max) * 100);
  return `
    <div class="role-bar-row">
      <div class="role-bar-lbl mono">${label}</div>
      <div class="role-bar-track"><div class="role-bar-fill" style="width:${pct}%; background:${color};"></div></div>
      <div class="role-bar-val mono">${valueLabel}</div>
    </div>`;
}

function renderRolesPanel(state) {
  renderNavbar("roles", true);
  const overrides = state.params.roleOverride || {};
  const suggestion = state.roleSuggestion || {};
  const rows = ROLE_ORDER.map((key) => ({
    key,
    ...(suggestion[key] || { scarNorm: 1, nOwned: 0, nFree: 0, fvmOwned: 0, fvmFree: 0, gapPct: 0, recommended: 1 }),
  }));

  const maxSupply = Math.max(...rows.map((r) => r.nOwned + r.nFree), 1);
  const maxGap = Math.max(...rows.map((r) => r.gapPct), 1);

  appBody.innerHTML = `
    <div>
      <h1>Modificatori Ruolo</h1>
      <p class="sub">Modificatore manuale per ruolo (es. 1.20 = +20%): entra diretto in "mod" nel Valore finale del giocatore (S×(1+mod+duttilita+eta)), NON moltiplicato per la scarsita' (ScarNorm/Consigliato qui sotto sono solo un riferimento, mai applicati in automatico). Valore 1.0 = nessun effetto — decidi tu.</p>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Giocatori disponibili per ruolo</h2>
        <span class="hint">Posseduti (verde) vs liberi/svincolo (blu), fuori lista esclusi</span></div>
      <div class="legend-row sub">
        <span><i class="dot" style="background:var(--accent);"></i> Posseduti</span>
        <span><i class="dot" style="background:var(--chart-blue);"></i> Liberi</span>
      </div>
      ${rows.map((r) => `
        <div class="role-bar-row">
          <div class="role-bar-lbl mono">${r.key}</div>
          <div class="role-bar-track role-bar-track-double">
            <div class="role-bar-fill" style="width:${Math.max(2, r.nOwned / maxSupply * 100)}%; background:var(--accent); top:0;"></div>
            <div class="role-bar-fill" style="width:${Math.max(2, r.nFree / maxSupply * 100)}%; background:var(--chart-blue); top:10px;"></div>
          </div>
          <div class="role-bar-val mono">${r.nOwned}/${r.nOwned + r.nFree}</div>
        </div>
      `).join("")}
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Gap FVM posseduti vs liberi (%)</h2>
        <span class="hint">Quanto sono piu' scarsi i liberi rimasti — piu' alto = piu' difficile sostituire chi possiedi</span></div>
      ${rows.map((r) => roleBarRow(r.key, r.gapPct, maxGap, "var(--gold)", `${r.gapPct.toFixed(0)}%`)).join("")}
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Tabella completa e modificatori</h2></div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Ruolo</th><th>Nome</th><th>Poss.</th><th>Liberi</th>
              <th>FVM poss.</th><th>FVM liberi</th><th>Gap%</th>
              <th>ScarNorm</th><th>Consigliato</th><th>Modificatore</th>
            </tr>
          </thead>
          <tbody>
            ${rows.map((r) => `
              <tr>
                <td class="mono">${r.key}</td>
                <td>${ROLE_LABELS[r.key]}</td>
                <td class="mono sub">${r.nOwned}</td>
                <td class="mono sub">${r.nFree}</td>
                <td class="mono sub">${r.fvmOwned.toFixed(1)}</td>
                <td class="mono sub">${r.fvmFree.toFixed(1)}</td>
                <td class="mono sub">${r.gapPct.toFixed(0)}%</td>
                <td class="mono sub">${r.scarNorm.toFixed(2)}</td>
                <td class="mono sub">${r.recommended.toFixed(2)}</td>
                <td><input class="input mono" style="width:6rem;" id="role-override-${r.key}" value="${
                  overrides[r.key] !== undefined ? overrides[r.key] : 1.0
                }" /></td>
              </tr>`).join("")}
          </tbody>
        </table>
      </div>
    </div>

    <div class="footer-bar">
      <div></div>
      <div class="footer-actions">
        <button class="btn btn-ghost" id="roles-back-btn">← Torna alla dashboard</button>
        <button class="btn btn-primary" id="roles-apply-btn">Salva</button>
      </div>
    </div>
    <p class="sub" id="roles-status"></p>
  `;

  document.getElementById("roles-back-btn").addEventListener("click", () => loadAndRender());

  document.getElementById("roles-apply-btn").addEventListener("click", async () => {
    const statusEl = document.getElementById("roles-status");
    const roleOverride = {};
    for (const key of ROLE_ORDER) {
      const val = parseFloat(document.getElementById(`role-override-${key}`).value);
      if (Number.isNaN(val) || val <= 0) {
        statusEl.textContent = `Errore: modificatore "${key}" non valido (deve essere > 0).`;
        return;
      }
      roleOverride[key] = val;
    }

    statusEl.textContent = "MATLAB sta ricalcolando i punteggi…";
    try {
      await postAction("setRoleOverride", { roleOverride });
      const newState = await fetchState();
      renderRolesPanel(newState);
    } catch (err) {
      statusEl.textContent = `Errore: ${err.message}`;
    }
  });
}

function renderPlayerList(state) {
  renderNavbar("players", true);
  const scoresById = new Map(state.scores.map((s) => [s.id, s]));
  const rows = state.players.map((p) => {
    const s = scoresById.get(p.id) || { fScore: null, qScore: null, score: null, mod: null, flex: null, etaWeight: null, assembleWeight: null, creditoStimato: null, incassoNettoDecisionale: null };
    return {
      id: p.id,
      nome: p.nome,
      ruolo: p.roleMantra,
      fantaSquadra: p.team || "",
      owned: p.owned,
      fuoriLista: p.fuoriLista,
      fvm: p.fvm,
      quot: p.quot,
      costo: p.costo,
      fScore: s.fScore,
      qScore: s.qScore,
      score: s.score,
      mod: s.mod,
      duttilita: s.flex !== null && s.flex !== undefined ? s.flex - 1 : null,
      etaWeight: s.etaWeight,
      assembleWeight: s.assembleWeight,
      // Sia il credito stimato (lordo) che il netto svincolo hanno senso solo per chi e'
      // posseduto -- sono valori derivati dal tetto crediti della lega assegnato a chi la
      // rosa ce l'ha gia'; un libero non ha nessun valore "preso dai crediti massimi"
      // (2026-08-05, richiesta esplicita del proprietario). Restano null -> "--" in tabella.
      creditoStimato: p.owned ? s.creditoStimato : null,
      nettoSvincolo: p.owned ? s.incassoNettoDecisionale : null,
    };
  });

  let sortKey = "creditoStimato";
  let sortDir = -1;
  let filterText = "";
  const filterRoles = new Set();
  let filterSquadra = "";
  let filterOwned = ""; // "" = tutti, "owned" = solo posseduti, "free" = solo svincolati/liberi, "fuorilista" = estero/fuori lista

  const roles = Array.from(new Set(rows.flatMap((r) => (r.ruolo || "").split("/")).filter(Boolean))).sort();
  const squadre = Array.from(new Set(rows.map((r) => r.fantaSquadra).filter(Boolean))).sort();

  function renderTable() {
    const filtered = rows.filter((r) => {
      if (filterText && !r.nome.toLowerCase().includes(filterText.toLowerCase())) return false;
      if (filterRoles.size > 0 && !(r.ruolo || "").split("/").some((tok) => filterRoles.has(tok))) return false;
      if (filterSquadra && r.fantaSquadra !== filterSquadra) return false;
      if (filterOwned === "owned" && !r.owned) return false;
      if (filterOwned === "free" && (r.owned || r.fuoriLista)) return false;
      if (filterOwned === "fuorilista" && !r.fuoriLista) return false;
      return true;
    });
    filtered.sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      const aNull = av === null || av === undefined;
      const bNull = bv === null || bv === undefined;
      // Entrambi senza valore (liberi, es. su creditoStimato/nettoSvincolo): raggruppali
      // comunque per FVM decrescente, altrimenti finiscono in ordine casuale e i migliori
      // liberi (es. attaccanti forti appena aggiunti) si perdono in mezzo a centinaia di
      // righe (2026-08-05: "Ramos/Kolo Muani sono spariti" -- non erano spariti, solo
      // impossibili da trovare scorrendo per via di un comparator rotto).
      if (aNull && bNull) return b.fvm - a.fvm;
      if (aNull) return 1;
      if (bNull) return -1;
      if (typeof av === "string") return sortDir * av.localeCompare(bv);
      return sortDir * (av - bv);
    });

    const fmt = (v, digits) => (v === null || v === undefined ? "—" : Number(v).toFixed(digits));

    document.getElementById("player-table-body").innerHTML = filtered
      .map(
        (r) => `<tr>
          <td class="team-name">${r.nome}${r.fuoriLista ? ' <span class="pill pill-out">fuori lista</span>' : ""}</td>
          <td>${r.ruolo}</td>
          <td>${r.fantaSquadra || "—"}</td>
          <td class="num mono">${fmtCredit(r.costo)}</td>
          <td class="num mono">${r.fvm}</td>
          <td class="num mono">${r.quot}</td>
          <td class="num mono">${fmt(r.fScore, 3)}</td>
          <td class="num mono">${fmt(r.qScore, 3)}</td>
          <td class="num mono" style="font-weight:700;">${fmt(r.score, 3)}</td>
          <td class="num mono">${fmt(r.mod, 3)}</td>
          <td class="num mono">${fmt(r.duttilita, 3)}</td>
          <td class="num mono">${fmt(r.etaWeight, 3)}</td>
          <td class="num mono" style="font-weight:700; color:var(--gold);">${fmt(r.assembleWeight, 3)}</td>
          <td class="num mono" style="font-weight:700; color:var(--accent);">${fmtCredit(r.creditoStimato)}</td>
          <td class="num mono" style="font-weight:700; color:var(--gold);">${fmtCredit(r.nettoSvincolo)}</td>
        </tr>`
      )
      .join("");
    document.getElementById("player-count").textContent = `${filtered.length} / ${rows.length} giocatori`;
  }

  const columns = [
    { key: "nome", label: "Nome" },
    { key: "ruolo", label: "Ruolo" },
    { key: "fantaSquadra", label: "FantaSquadra" },
    { key: "costo", label: "Costo", num: true },
    { key: "fvm", label: "FVM", num: true },
    { key: "quot", label: "QUOT", num: true },
    { key: "fScore", label: "F_score", num: true },
    { key: "qScore", label: "Q_score", num: true },
    { key: "score", label: "S", num: true },
    { key: "mod", label: "mod", num: true },
    { key: "duttilita", label: "duttilità", num: true },
    { key: "etaWeight", label: "età", num: true },
    { key: "assembleWeight", label: "Valore", num: true },
    { key: "creditoStimato", label: "Credito stimato (lordo)", num: true },
    { key: "nettoSvincolo", label: "Netto svincolo", num: true },
  ];

  const ap = state.params;

  appBody.innerHTML = `
    <div class="toolbar">
      <div class="left">
        <h1>Lista giocatori</h1>
        <p class="sub" id="player-count"></p>
      </div>
      <div class="right">
        <a class="btn btn-primary" href="/api/export-listone" download>Esporta listone xlsx</a>
      </div>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Conversione in crediti</h2>
        <span class="hint">Crediti = (Valore + offsetC)^expK, riscalato al budget lega, floor minimo</span></div>
      <div class="field-row">
        <div class="field">
          <label for="auction-offsetc">offsetC</label>
          <input class="input mono" id="auction-offsetc" value="${ap.auctionOffsetC}" />
        </div>
        <div class="field">
          <label for="auction-expk">expK</label>
          <input class="input mono" id="auction-expk" value="${ap.auctionExpK}" />
        </div>
        <div class="field">
          <label for="auction-floor">floor (crediti minimi)</label>
          <input class="input mono" id="auction-floor" value="${ap.auctionFloor}" />
        </div>
        <div class="field" style="justify-content:flex-end;">
          <label>&nbsp;</label>
          <button class="btn btn-primary" id="auction-apply-btn">Salva</button>
        </div>
      </div>
      <p class="sub" id="auction-status"></p>
    </div>

    <div class="field-row">
      <div class="field">
        <label for="player-search">Cerca nome</label>
        <input class="input" id="player-search" placeholder="es. Martinez" />
      </div>
      <div class="field" style="max-width:260px;">
        <label for="player-squadra-filter">FantaSquadra</label>
        <select class="input" id="player-squadra-filter">
          <option value="">Tutte</option>
          ${squadre.map((s) => `<option value="${s}">${s}</option>`).join("")}
        </select>
      </div>
      <div class="field" style="max-width:220px;">
        <label for="player-owned-filter">Possesso</label>
        <select class="input" id="player-owned-filter">
          <option value="">Tutti</option>
          <option value="owned">Solo posseduti</option>
          <option value="free">Solo svincolati (liberi, esclusi estero)</option>
          <option value="fuorilista">Fuori lista / estero</option>
        </select>
      </div>
    </div>
    <div class="field">
      <label>Ruolo (multi-selezione)</label>
      <div id="player-role-filter" style="display:flex; flex-wrap:wrap; gap:6px; padding:8px 0;">
        ${roles
          .map(
            (r) =>
              `<button type="button" class="btn btn-ghost role-pill" data-role="${r}" style="padding:4px 10px; font-size:12px;">${r}</button>`
          )
          .join("")}
      </div>
    </div>
    <div class="panel" style="padding:0; overflow:hidden;">
      <div class="table-wrap" style="border:none; border-radius:0; max-height:520px; overflow-y:auto;">
        <table>
          <thead><tr>
            ${columns
              .map((c) => `<th ${c.num ? 'class="num"' : ""} data-sort-key="${c.key}" style="cursor:pointer;">${c.label}</th>`)
              .join("")}
          </tr></thead>
          <tbody id="player-table-body"></tbody>
        </table>
      </div>
    </div>
    <div class="footer-bar">
      <div></div>
      <div class="footer-actions"><button class="btn btn-ghost" id="players-back-btn">← Torna alla dashboard</button></div>
    </div>
  `;

  renderTable();

  document.getElementById("auction-apply-btn").addEventListener("click", async () => {
    const statusEl = document.getElementById("auction-status");
    const offsetC = parseFloat(document.getElementById("auction-offsetc").value);
    const expK = parseFloat(document.getElementById("auction-expk").value);
    const floorCredito = parseFloat(document.getElementById("auction-floor").value);
    if ([offsetC, expK, floorCredito].some((v) => Number.isNaN(v))) {
      statusEl.textContent = "Errore: valori non validi.";
      return;
    }
    statusEl.textContent = "MATLAB sta ricalcolando i punteggi…";
    try {
      await postAction("setAuctionParams", { offsetC, expK, floorCredito });
      const newState = await fetchState();
      renderPlayerList(newState);
    } catch (err) {
      statusEl.textContent = `Errore: ${err.message}`;
    }
  });

  document.getElementById("player-search").addEventListener("input", (e) => {
    filterText = e.target.value;
    renderTable();
  });
  document.querySelectorAll(".role-pill").forEach((btn) => {
    btn.addEventListener("click", () => {
      const role = btn.dataset.role;
      if (filterRoles.has(role)) {
        filterRoles.delete(role);
        btn.classList.remove("btn-primary");
        btn.classList.add("btn-ghost");
      } else {
        filterRoles.add(role);
        btn.classList.remove("btn-ghost");
        btn.classList.add("btn-primary");
      }
      renderTable();
    });
  });
  document.getElementById("player-squadra-filter").addEventListener("change", (e) => {
    filterSquadra = e.target.value;
    renderTable();
  });
  document.getElementById("player-owned-filter").addEventListener("change", (e) => {
    filterOwned = e.target.value;
    renderTable();
  });
  document.querySelectorAll("[data-sort-key]").forEach((th) => {
    th.addEventListener("click", () => {
      const key = th.dataset.sortKey;
      if (sortKey === key) sortDir *= -1;
      else {
        sortKey = key;
        sortDir = -1;
      }
      renderTable();
    });
  });
  document.getElementById("players-back-btn").addEventListener("click", () => loadAndRender());
}

function renderSvincoliRows(roster) {
  return roster
    .map(
      (p) => `<tr>
      <td class="team-name">${p.nome}${p.fuoriLista ? ' <span class="pill pill-out">estero/fuori lista</span>' : ""}</td>
      <td class="mono sub">${p.ruolo}</td>
      <td class="num mono sub">${fmtCredit(p.costo)}</td>
      <td class="num mono">${fmtCredit(p.lordo)}</td>
      <td class="num mono" style="font-weight:700;">${fmtCredit(p.netto)}</td>
      <td class="num mono"><span class="pill ${p.delta >= 0 ? "pill-plus" : "pill-minus"}">${p.delta >= 0 ? "+" : ""}${Math.ceil(p.delta)}</span></td>
    </tr>`
    )
    .join("");
}

function renderTeamPanel(state, teamName) {
  renderNavbar("dashboard", true);
  const team = state.teams.table.find((t) => t.name === teamName);
  if (!team) {
    renderError(`Squadra "${teamName}" non trovata.`);
    return;
  }

  const scoresById = new Map(state.scores.map((s) => [s.id, s]));
  const roster = state.players
    .filter((p) => p.owned && p.team === teamName)
    .map((p) => {
      const s = scoresById.get(p.id) || {};
      const lordo = s.creditoStimato || 0;
      const netto = s.incassoNettoDecisionale || 0;
      const costo = p.costo || 0;
      const mantraRoles = (p.roleMantra || "").split("/").filter(Boolean);
      return { nome: p.nome, ruolo: p.roleMantra || "", mantraRoles, costo, lordo, netto, delta: netto - costo, fuoriLista: !!p.fuoriLista };
    })
    .sort((a, b) => b.lordo - a.lordo);

  const formationResults = MANTRA_MODULES.map((m) => bestXIForModule(roster, m)).sort((a, b) => {
    if (a.feasible !== b.feasible) return a.feasible ? -1 : 1;
    return (b.totalValue || 0) - (a.totalValue || 0);
  });
  const bestFormation = formationResults.find((f) => f.feasible) || null;

  const countByRole = ROLE_ORDER.map((r) => roster.filter((p) => p.ruolo.split("/").includes(r)).length);

  const avgByRole = (players) =>
    ROLE_ORDER.map((r) => {
      const vals = players.filter((p) => p.ruolo.split("/").includes(r)).map((p) => p.lordo);
      return vals.length ? vals.reduce((s, v) => s + v, 0) / vals.length : 0;
    });

  const allOwned = state.players
    .filter((p) => p.owned)
    .map((p) => ({ ruolo: p.roleMantra || "", lordo: (scoresById.get(p.id) || {}).creditoStimato || 0 }));

  const teamByRole = avgByRole(roster);
  const leagueByRole = avgByRole(allOwned);

  const banca = isOverrideSet(team.bankOverride) ? team.bankOverride : team.creditiIniziali;
  const lordoTot = roster.reduce((s, p) => s + p.lordo, 0);
  const nettoTot = roster.reduce((s, p) => s + p.netto, 0);

  const styles = getComputedStyle(document.documentElement);
  const accentColor = styles.getPropertyValue("--accent").trim();
  const goldColor = styles.getPropertyValue("--gold").trim();

  appBody.innerHTML = `
    <div class="toolbar">
      <div class="left">
        <h1 style="font-size:22px;">${team.name}</h1>
        <span class="hint">${roster.length} giocatori in rosa</span>
      </div>
      <div class="right">
        <button class="btn btn-ghost btn-sm" id="team-back-btn">← Torna alla dashboard</button>
      </div>
    </div>

    <div class="stat-grid">
      <div class="stat"><span class="k">Banca</span><span class="v">${banca}</span></div>
      <div class="stat"><span class="k">Bonus/Malus</span><span class="v ${team.bonusMalusSum >= 0 ? "accent" : "gold"}">${team.bonusMalusSum}</span></div>
      <div class="stat"><span class="k">Valore rosa (lordo)</span><span class="v gold">${Math.ceil(lordoTot)}</span></div>
      <div class="stat"><span class="k">Netto se svincolasse tutta</span><span class="v accent">${Math.ceil(nettoTot)}</span></div>
    </div>

    <div class="grid-2">
      <div class="panel">
        <div class="panel-head"><h2>Giocatori per ruolo</h2><span class="hint">Rosa attuale</span></div>
        <canvas id="team-role-bar" width="480" height="230" style="width:100%; height:230px;"></canvas>
      </div>
      <div class="panel">
        <div class="panel-head"><h2>Profilo squadra</h2><span class="hint">Valore medio per ruolo</span></div>
        <div class="legend-row sub">
          <span><i class="dot" style="background:${accentColor};"></i> ${team.name}</span>
          <span><i class="dot" style="background:${goldColor};"></i> Media lega</span>
        </div>
        <canvas id="team-radar" width="480" height="300" style="width:100%; height:300px;"></canvas>
      </div>
    </div>

    <div class="panel">
      <div class="panel-head"><h2>Moduli fattibili</h2>
        <span class="hint">Formazione titolare che massimizza il valore stimato, coprendo tutti i ruoli richiesti</span></div>
      ${roster.length === 0 ? '<p class="sub">Nessun giocatore posseduto.</p>' : `
      <div class="table-wrap"><table>
        <thead><tr><th>Modulo</th><th>Stato</th><th class="num">Valore titolari</th></tr></thead>
        <tbody>${formationResults
          .map((f, i) => {
            const isBest = bestFormation && f.formation === bestFormation.formation && i === 0;
            const statusCell = f.feasible
              ? `<span class="pill ${isBest ? "pill-plus" : "pill-upd"}">${isBest ? "consigliato" : "fattibile"}</span>`
              : `<span class="pill pill-minus">mancano: ${f.missingSlots.join(", ")}</span>`;
            return `<tr>
              <td class="team-name mono">${f.formation}</td>
              <td>${statusCell}</td>
              <td class="num mono" style="font-weight:${isBest ? 700 : 400};">${f.feasible ? fmtCredit(f.totalValue) : "—"}</td>
            </tr>`;
          })
          .join("")}</tbody>
      </table></div>`}
    </div>

    ${bestFormation ? `
    <div class="grid-2">
      <div class="panel">
        <div class="panel-head"><h2>Titolari — modulo ${bestFormation.formation}</h2>
          <span class="hint">Valore ${fmtCredit(bestFormation.totalValue)}</span></div>
        <div class="table-wrap"><table>
          <thead><tr><th>Ruolo</th><th>Nome</th><th class="num">Valore</th></tr></thead>
          <tbody>${bestFormation.slots
            .map((slot, i) => {
              const p = bestFormation.assigned[i];
              return `<tr>
                <td class="mono sub">${slot.roles.join("/")}</td>
                <td class="team-name">${p ? p.nome : "—"}</td>
                <td class="num mono">${p ? fmtCredit(p.lordo) : "—"}</td>
              </tr>`;
            })
            .join("")}</tbody>
        </table></div>
      </div>
      <div class="panel">
        <div class="panel-head"><h2>Analisi cambi</h2>
          <span class="hint">Panchina disponibile col modulo ${bestFormation.formation}, per profondita' di ruolo</span></div>
        ${bestFormation.relevantRoles
          .map((r) => {
            const players = bestFormation.bench.filter((p) => p.mantraRoles.includes(r)).sort((a, b) => b.lordo - a.lordo);
            const pillClass = players.length === 0 ? "pill-minus" : players.length === 1 ? "pill-upd" : "pill-plus";
            return `
            <div class="field-row" style="align-items:baseline; margin-bottom:6px;">
              <span class="mono sub" style="min-width:2.5rem;">${r}</span>
              <span class="pill ${pillClass}">${players.length} in panchina</span>
              <span class="sub" style="flex:2; min-width:0;">${players.map((p) => p.nome).join(", ") || "nessun cambio disponibile — rischio in caso di infortunio/squalifica"}</span>
            </div>`;
          })
          .join("")}
      </div>
    </div>` : `
    <div class="panel">
      <p class="sub">Nessun modulo Mantra e' coperto dalla rosa attuale (mancano giocatori in uno o piu' ruoli).</p>
    </div>`}

    <div class="panel">
      <div class="panel-head"><h2>Studio svincoli — rosa ${team.name}</h2>
        <span class="hint">Costo pagato vs valore lordo attuale vs netto svincolo decisionale</span></div>
      ${
        roster.length === 0
          ? '<p class="sub">Nessun giocatore posseduto.</p>'
          : `<input class="input mono" id="svincoli-filter" placeholder="Filtra per nome…" style="margin-bottom:10px; width:100%; max-width:20rem;" />
      <div class="table-wrap"><table>
        <thead><tr><th>Nome</th><th>Ruolo</th><th class="num">Costo</th><th class="num">Lordo</th><th class="num">Netto</th><th class="num">Plus/Minus</th></tr></thead>
        <tbody id="svincoli-tbody">${renderSvincoliRows(roster)}</tbody>
      </table></div>`
      }
    </div>

    <div class="footer-bar"><div></div><div class="footer-actions"><button class="btn btn-ghost" id="team-back-btn-2">← Torna alla dashboard</button></div></div>
  `;

  drawBarChart(document.getElementById("team-role-bar"), ROLE_ORDER, countByRole, { color: accentColor });
  drawRadar(
    document.getElementById("team-radar"),
    ROLE_ORDER,
    [
      { values: teamByRole, color: accentColor },
      { values: leagueByRole, color: goldColor, dashed: true },
    ],
    {}
  );

  document.getElementById("team-back-btn").addEventListener("click", () => loadAndRender());
  document.getElementById("team-back-btn-2").addEventListener("click", () => loadAndRender());

  const svincoliFilter = document.getElementById("svincoli-filter");
  if (svincoliFilter) {
    svincoliFilter.addEventListener("input", () => {
      const q = svincoliFilter.value.trim().toLowerCase();
      const filtered = q ? roster.filter((p) => p.nome.toLowerCase().includes(q)) : roster;
      document.getElementById("svincoli-tbody").innerHTML = renderSvincoliRows(filtered);
    });
  }
}

async function renderLeagueBar() {
  const response = await fetch("/api/leagues");
  const { leagues, active } = await response.json();
  const bar = document.getElementById("league-bar");

  bar.innerHTML = `
    <select class="input mono" id="league-select" style="padding:6px 10px; font-size:12px;">
      ${leagues.map((slug) => `<option value="${slug}" ${slug === active ? "selected" : ""}>${slug}</option>`).join("")}
    </select>
    <button class="btn btn-ghost btn-sm" id="new-league-btn">+ Nuova lega</button>
  `;

  document.getElementById("league-select").addEventListener("change", async (event) => {
    await fetch("/api/leagues/active", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ slug: event.target.value }),
    });
    await loadAndRender();
  });

  document.getElementById("new-league-btn").addEventListener("click", () => {
    openModal({
      title: "Nuova lega",
      fields: [{ key: "name", label: "Nome lega", value: "" }],
      onSubmit: async ({ name }) => {
        if (!name || name.trim().length === 0) throw new Error("Il nome e' obbligatorio.");
        const createResponse = await fetch("/api/leagues", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name }),
        });
        if (!createResponse.ok) {
          const body = await createResponse.json();
          throw new Error(body.detail || "Impossibile creare la lega.");
        }
        await loadAndRender();
      },
    });
  });
}

function renderNavbar(active, hasLeague) {
  const items = [
    { key: "dashboard", label: `${icon("grid", 14)}Dashboard`, fn: () => loadAndRender() },
    { key: "players", label: `${icon("list", 14)}Lista giocatori`, fn: () => fetchState().then(renderPlayerList) },
    { key: "formula", label: "&phi; Formula valori", fn: () => fetchState().then(renderFormulaPanel) },
    { key: "roles", label: `${icon("users", 14)}Ruoli`, fn: () => fetchState().then(renderRolesPanel) },
    { key: "age", label: `${icon("calendar", 14)}Età`, fn: () => fetchState().then(renderAgePanel) },
    { key: "tax", label: `${icon("percent", 14)}Tasse`, fn: () => fetchState().then(renderTaxPanel) },
  ];
  const nav = document.getElementById("navbar");
  if (!hasLeague) {
    nav.innerHTML = "";
    return;
  }
  nav.innerHTML = items
    .map(
      (it) => `<button class="btn btn-ghost btn-sm nav-item" data-nav="${it.key}" style="${
        active === it.key ? "background:var(--ink-750); color:var(--text-hi);" : ""
      }">${it.label}</button>`
    )
    .join("");
  items.forEach((it) => {
    nav.querySelector(`[data-nav="${it.key}"]`).addEventListener("click", it.fn);
  });
}

async function loadAndRender() {
  await renderLeagueBar();
  const state = await fetchState();
  if (!state.teams || state.teams.table.length === 0) {
    renderNavbar("dashboard", false);
    renderUploadScreen();
  } else {
    renderNavbar("dashboard", true);
    renderDashboard(state);
  }
}

loadAndRender();

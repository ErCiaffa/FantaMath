const appBody = document.getElementById("app-body");

async function fetchState() {
  const response = await fetch("/api/state");
  return response.json();
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
      <div class="eyebrow">Primo avvio</div>
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
      <div class="eyebrow">Primo avvio</div>
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
  const totalCredits = teams.reduce((sum, t) => sum + t.creditiIniziali, 0);
  const totalBank = teams.reduce((sum, t) => sum + (isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali), 0);

  appBody.innerHTML = `
    <div class="toolbar">
      <div class="left">
        <div class="eyebrow">Lega caricata</div>
        <h1 style="font-size:22px;">Dashboard</h1>
      </div>
      <div class="right">
        <button class="btn btn-ghost btn-sm" id="update-csv-btn">↻ Carica nuovo CSV (aggiorna)</button>
      </div>
    </div>
    <div class="stat-grid">
      <div class="stat"><span class="k">Squadre</span><span class="v">${teams.length}</span></div>
      <div class="stat"><span class="k">Epsilon</span><span class="v gold">${state.epsilon}</span></div>
      <div class="stat"><span class="k">Crediti in circolazione</span><span class="v">${totalCredits}</span></div>
      <div class="stat"><span class="k">Banche residue totali</span><span class="v accent">${totalBank}</span></div>
    </div>
    <div class="panel" style="padding:0; overflow:hidden;">
      <div class="table-wrap" style="border:none; border-radius:0;"><table>
        <thead><tr><th>Squadra</th><th class="num">Crediti iniziali</th><th class="num">Valore squadra</th><th class="num">Banca residua</th><th></th></tr></thead>
        <tbody>${teams
          .map((t) => {
            const bank = isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali;
            return `<tr>
              <td class="team-name">${t.name}</td>
              <td class="num mono">${t.creditiIniziali}</td>
              <td class="num mono">${t.teamValue}</td>
              <td class="num"><span class="bank-value ${bank >= 0 ? "pos" : "neg"}" data-bank-for="${t.name}">${bank}</span>
                <span class="edit-icon" data-edit-for="${t.name}">✎</span></td>
              <td class="num"><button class="bm-btn" data-bonus-for="${t.name}">± B/M</button></td>
            </tr>`;
          })
          .join("")}</tbody>
      </table></div>
    </div>
  `;

  teams.forEach((t) => {
    document.querySelector(`[data-edit-for="${CSS.escape(t.name)}"]`).addEventListener("click", () => {
      const currentBank = isOverrideSet(t.bankOverride) ? t.bankOverride : t.creditiIniziali;
      openModal({
        title: `Nuova banca residua — ${t.name}`,
        fields: [{ key: "value", label: "Banca residua", value: currentBank }],
        onSubmit: async ({ value }) => {
          const numeric = parseFloat(value);
          if (Number.isNaN(numeric)) throw new Error("Inserisci un numero valido.");
          await postAction("setBankOverride", { teamName: t.name, value: numeric });
          await loadAndRender();
        },
      });
    });
    document.querySelector(`[data-bonus-for="${CSS.escape(t.name)}"]`).addEventListener("click", () => {
      openModal({
        title: `Bonus / Malus — ${t.name}`,
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
}

function renderUploadForUpdate(knownTeamNames) {
  appBody.innerHTML = `
    <div>
      <div class="eyebrow">Aggiornamento</div>
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

async function loadAndRender() {
  const state = await fetchState();
  if (!state.teams || state.teams.table.length === 0) {
    renderUploadScreen();
  } else {
    renderDashboard(state);
  }
}

loadAndRender();

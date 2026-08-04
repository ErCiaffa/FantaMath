# FantaManager

Motore di valutazione economica per una lega Fantacalcio manageriale (regole Mantra)
pluriennale. Calcola il valore di svincolo e di asta di ogni giocatore a partire da FVM e
quotazione ufficiali, scarsità di ruolo, età e tassazione; gestisce budget, rose e
transazioni delle squadre nel tempo; esporta liste prezzi utilizzabili in asta e agli
svincoli reali.

## Indice

- [Cosa fa](#cosa-fa)
- [Per i membri della lega](#per-i-membri-della-lega)
- [Per il proprietario della lega](#per-il-proprietario-della-lega)
- [Architettura](#architettura)
- [Struttura del repository](#struttura-del-repository)
- [Test](#test)
- [Documentazione](#documentazione)

## Cosa fa

A differenza di un semplice listone/quotazioni, FantaManager combina:

- **Scarsità di ruolo reale**, calcolata sui dati della lega attiva (non una stima
  generica).
- **Modello economico multi-stagione**: plusvalenza/minusvalenza, tassazione differenziata
  per motivo di svincolo (estero vs. decisionale).
- **Invariante di budget verificabile**: se tutti i giocatori posseduti venissero
  svincolati oggi, contemporaneamente, il netto totale (dopo tasse) torna esatto al budget
  della lega — non un'approssimazione, un vincolo matematico verificato ad ogni ricalcolo.
- **Parametri completamente tarabili** dal proprietario della lega (normalizzazione,
  modificatori di ruolo, età, tassazione, conversione in crediti) — nessun numero nascosto
  nel codice.

La formula completa, con ogni passaggio e razionale, è documentata in
[`docs/FORMULE.md`](docs/FORMULE.md).

## Per i membri della lega

Apri l'URL fornito dal proprietario della lega (tipicamente `http://<host>:8420`).

| Pagina | Cosa mostra |
|---|---|
| **Dashboard** | Banca, bonus/malus, valore rosa (netto svincolo) e totale, per ogni squadra |
| **Lista giocatori** | Listone completo: ricerca per nome, filtro ruolo (multi-selezione), filtro FantaSquadra, filtro possesso (posseduti/svincolati). Esportazione xlsx del listone aggiornato |
| **Dettaglio squadra** | Rosa, miglior modulo Mantra schierabile, profondità panchina per ruolo, valore lordo/netto di ogni giocatore |
| **Ruoli / Età / Tasse / Formula valori** | Parametri di calcolo attualmente in uso — sola lettura per i membri, modificabili solo dal proprietario |

## Per il proprietario della lega

### Requisiti

- MATLAB (con licenza) — motore di calcolo.
- Python 3.10+ — bridge web.

### Avvio

```bash
cd FantaManager

# Setup una tantum
python -m venv .venv
.venv\Scripts\pip install -r server\requirements.txt

# Ad ogni avvio: due processi indipendenti, entrambi devono restare attivi
.venv\Scripts\python.exe -m uvicorn server.main:app --host 127.0.0.1 --port 8420
matlab -batch "addpath(pwd); watchLeague"
```

Apri `http://127.0.0.1:8420/`. Il primo avvio guida nella creazione di una lega: caricamento
del listone (CSV/xlsx) e crediti iniziali per squadra.

### Aggiornare il listone

Pulsante "Carica nuovo CSV" in dashboard. Il merge con il listone esistente:

- aggiorna ruolo, squadra, FVM e quotazione per ogni giocatore già presente;
- marca come fuori lista chi non compare più nel nuovo listone;
- inserisce i nuovi giocatori senza FantaSquadra né costo assegnati.

`Costo` e `FantaSquadra` di un giocatore già posseduto non vengono mai sovrascritti in
automatico.

### Dati della lega

`config/` (rose, crediti, transazioni — i dati reali della lega) **non è versionato**: resta
locale a chi fa girare l'app e non viene mai pubblicato su GitHub.

## Architettura

```
Frontend (HTML/CSS/JS statico)
        │  HTTP
        ▼
Bridge FastAPI (server/) ── coda file (queue.json) ──▶ Poller MATLAB (watchLeague.m, tick 2s)
        ▲                                                        │
        └──────────────── lega.json (stato esportato) ◀──────────┘
```

- **Motore** (`+src/+state`, `+src/+io`, `+src/+engine`): MATLAB. Logica di business,
  validazione, formule di valutazione.
- **Bridge** (`server/`): FastAPI. Espone lo stato come JSON, riceve le azioni dell'utente
  (modifica banca, bonus/malus, upload listone, cambio parametri) e le mette in coda.
- **Poller** (`watchLeague.m`): MATLAB, processo separato. Applica le azioni in coda allo
  stato, ricalcola i punteggi, riesporta il JSON. Nessuna scrittura diretta dal web allo
  stato — tutte le modifiche passano dalla coda.
- **Frontend** (`frontend/`): HTML/CSS/JS statico, nessun framework.

Bridge e poller sono processi indipendenti: modifiche al codice MATLAB o Python richiedono
il riavvio del rispettivo processo (nessun hot-reload).

## Struttura del repository

```
+src/+state/       Stato della lega (LeagueState) e i suoi metodi
+src/+io/           Import/merge del listone, export JSON
+src/+engine/       Formule di valutazione (normalizzazione, scarsità, età, tasse, ...)
+src/+app/          Elaborazione della coda azioni (processQueue)
server/             Bridge FastAPI
frontend/           UI web statica
tests/              Test MATLAB (matlab.unittest) e fixture
server/tests/       Test Python (pytest)
docs/                Documentazione tecnica
```

## Test

```bash
# MATLAB
matlab -batch "addpath(pwd); runtests('tests', 'IncludeSubfolders', true)"

# Python
cd server && python -m pytest tests/ -q
```

## Documentazione

| Documento | Contenuto |
|---|---|
| [`docs/FORMULE.md`](docs/FORMULE.md) | Modello di valutazione completo: ogni formula, parametro e razionale |
| [`docs/normalizzazione-fvm-quot.md`](docs/normalizzazione-fvm-quot.md) | Analisi dettagliata della normalizzazione FVM/QUOT |
| [`docs/decisioni-e-logica.md`](docs/decisioni-e-logica.md) | Log cronologico delle decisioni di design prese durante lo sviluppo |
| [`PRODUCT.md`](PRODUCT.md) | Obiettivo del prodotto, utenti, vincoli |
| [`HANDOFF.md`](HANDOFF.md) | Stato del lavoro in corso, bug noti |

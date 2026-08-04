# FantaManager

Motore di valutazione economica per una lega Fantacalcio manageriale (Mantra) pluriennale.
Calcola il **valore di svincolo/asta** di ogni giocatore da FVM/QUOT ufficiali + scarsità
ruolo + età + tassazione, gestisce budget/rose/transazioni delle squadre nel tempo, ed
esporta liste prezzi da usare durante asta/svincoli reali.

Non è un semplice listone/quotazioni: la scarsità di ruolo è calcolata sui dati reali della
tua lega (non generica), il modello economico è multi-stagione (plusvalenza/minusvalenza,
tassazione differenziata per motivo di svincolo), e c'è un invariante di budget verificabile
— se tutti i giocatori posseduti venissero svincolati oggi, il netto totale (dopo tasse)
torna esatto al budget della lega.

## Per chi consulta (membri lega)

Apri l'URL della lega (te lo dà il proprietario, di solito `http://<ip>:8420`) e trovi:

- **Dashboard**: banca, bonus/malus, valore rosa (netto svincolo) e totale per ogni squadra.
- **Lista giocatori**: tutti i giocatori del listone, cerca per nome, filtra per ruolo
  (multi-selezione), FantaSquadra e possesso (posseduti/svincolati). Bottone "Esporta
  listone xlsx" per scaricare il listone completo aggiornato.
- **Dettaglio squadra** (click sul nome squadra in dashboard): rosa, miglior modulo Mantra
  schierabile, profondità panchina per ruolo, valore lordo/netto per giocatore.
- **Ruoli / Età / Tasse / Formula valori**: solo il proprietario lega modifica questi
  parametri — qui i membri possono comunque vedere come sono tarati.

Nessuno tranne il proprietario modifica parametri; i valori mostrati sono quelli ufficiali
della lega in quel momento.

## Per chi fa girare l'app (proprietario lega)

Serve MATLAB (con licenza) e Python 3.

```bash
# Setup una tantum
cd FantaManager
python -m venv .venv
.venv\Scripts\pip install -r server\requirements.txt

# Ogni volta che vuoi far girare l'app (due processi separati, entrambi devono restare avviati)
.venv\Scripts\python.exe -m uvicorn server.main:app --host 127.0.0.1 --port 8420
matlab -batch "addpath(pwd); watchLeague"
```

Poi apri `http://127.0.0.1:8420/`. Il primo avvio ti guida nella creazione di una lega
(carica il CSV/xlsx del listone, imposta i crediti iniziali per squadra).

**Aggiornare il listone**: usa il pulsante "Carica nuovo CSV" in dashboard — fa merge col
listone esistente (ruolo/squadra/FVM/QUOT aggiornati; chi non è più nel nuovo listone va
fuori lista; chi è nuovo entra senza FantaSquadra/Costo). `Costo`/`FantaSquadra` esistenti
non si toccano mai in automatico.

`config/` (dati reali della lega — rose, crediti, transazioni) **non è versionato**
apposta: resta locale a chi fa girare l'app, non finisce su GitHub.

## Architettura

- **Motore** (`+src/+state`, `+src/+io`, `+src/+engine`): MATLAB, logica di business e
  validazione, testato con `matlab.unittest` (74 test).
- **Bridge** (`server/`): FastAPI, espone `state` come JSON, riceve azioni via coda file
  (`config/leagues/<slug>/queue.json`) che MATLAB processa ogni 2 secondi.
- **Frontend** (`frontend/`): HTML/CSS/JS statico, nessun framework.

Il MATLAB poller (`watchLeague.m`) e il server FastAPI sono **due processi indipendenti**:
se modifichi il codice MATLAB o Python, vanno riavviati per caricare le modifiche (non
c'è hot-reload).

## Documentazione

- `PRODUCT.md` — cosa fa il prodotto e per chi, in breve.
- `docs/decisioni-e-logica.md` — log vivo di ogni decisione di design/parametro presa
  durante lo sviluppo, con le formule esatte usate dal motore. Leggilo prima di ogni
  modifica strutturale alla formula di valore.
- `docs/normalizzazione-fvm-quot.md` — analisi dettagliata della normalizzazione FVM/QUOT.
- `HANDOFF.md` — stato del lavoro in corso, prossimi passi, bug noti.

## Test

```bash
# MATLAB (74 test)
matlab -batch "addpath(pwd); runtests('tests', 'IncludeSubfolders', true)"

# Python (9 test)
cd server && python -m pytest tests/ -q
```

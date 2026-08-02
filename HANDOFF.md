# Handoff — 2026-08-03

## Come riprendere

1. Ferma processi vecchi prima di toccare `config/`:
   ```
   tasklist /FI "IMAGENAME eq MATLAB.exe"
   tasklist /FI "IMAGENAME eq python.exe"
   taskkill /F /PID <pid>   # per ognuno trovato
   ```
2. Riavvia entrambi (dalla cartella `FantaManager`):
   ```
   .venv\Scripts\python.exe -m uvicorn server.main:app --host 127.0.0.1 --port 8420
   matlab -batch "addpath(pwd); watchLeague"
   ```
3. Apri `http://127.0.0.1:8420/`. Lega attiva: `default` (10 squadre, 664 giocatori reali,
   listone caricato in `config/uploads/`).
4. Prima di ogni modifica strutturale allo stato: leggi `docs/decisioni-e-logica.md`
   (spiega ogni scelta fatta + le formule esatte) — **va aggiornato ad ogni nuova decisione**,
   non solo a fine sessione (istruzione permanente salvata in memoria).

## Stato

- **Setup lega, multi-lega, dashboard banca/bonus/malus, merge CSV**: completi e testati
  (47 test MATLAB, 9 test Python, tutti verdi).
- **Normalizzazione FVM/QUOT**: tarata sui dati reali. `alphaF=2, alphaQ=0.08, phi=0.40,
  pLow=0, pHigh=1`. Vincolo usato: "2-3 giocatori mediani = 1 top" (non simmetria
  statistica). Dettagli completi in `docs/normalizzazione-fvm-quot.md`.
- **Scarsità ruolo**: collegata (`roleDemand`/`roleScarcity`/`roleFactor`, portati da
  FantaMath con la fix B=Braccetto). Parametri: `qw=1, eta=1, mixOwned=1, nmax=3, beta=0.2,
  rho=1`.

## Prossimo passo — IMPORTANTE

`rho=1` è **sbagliato**: verificato che S×PesoRuolo con rho=1 fa sparire Martinez L. (il
miglior giocatore, S=0.992) dalla top 20, sostituito da difensori/centrocampisti mediocri
con RoleFactor alto. **Confermato dal proprietario della lega**: il valore deve venire
principalmente dalla forza del giocatore (S), la scarsità di ruolo deve attenuare, non
ribaltare. Prossima sessione: abbassare `rho` (provare 0.3-0.5) **mentre si costruisce
`assembleWeight` vero** — non un semplice prodotto S×PesoRuolo, quello era solo
un'anteprima grezza per mostrare il problema.

Poi in ordine: `ageWeight` (età) → `floorValue` (floor) → `assembleWeight` →
`auctionPrice`/`releaseValue` (conversione finale in crediti — usa l'epsilon già impostato).

## Bug noti, non risolti

- **Race intermittente lettura `lega.json`**: a volte il browser legge il file mentre
  MATLAB lo sta scrivendo, errore 500 temporaneo. Mitigato con scrittura atomica
  (`exportLegaJson.m`, temp file + rename) e retry lato frontend (`fetchState`, 3 tentativi)
  — capita ancora ogni tanto, causa probabile: il progetto vive dentro OneDrive
  (`C:\Users\ciaff\OneDrive\Desktop\Fanta\FantaManager`), il suo sync potrebbe interferire
  sui file in `config/`. Non indagato a fondo, contesto sessione esaurito. Se persiste,
  considerare di spostare `config/` fuori da OneDrive o escluderlo dal sync.
- **Poller MATLAB non riavvia da solo se crasha** (fix parziale: non crasha più su UNA
  lega rotta, ma se crasha per altro motivo va riavviato a mano — nessun supervisor).

## File chiave

- `docs/decisioni-e-logica.md` — log vivo di ogni decisione + formule, **aggiornare sempre**
- `docs/normalizzazione-fvm-quot.md` — analisi dettagliata normalizzazione (dati reali,
  grafici, metodo rank-esponenziale scartato con prove)
- `+src/+state/LeagueState.m` — stato centrale, tutti i metodi
- `+src/+app/processQueue.m` — applica le azioni dalla coda web→MATLAB
- `frontend/app.js` — tutta la UI (dashboard, formula, lista giocatori, navbar)

Branch: nessuno (repo locale, no remote). Tutto committato, niente in sospeso.

# Decisioni e logica — FantaManager

Documento vivo. Ogni scelta di design/parametro fatta durante lo sviluppo viene registrata
qui, con **perché**, non solo **cosa**. Ogni formula usata nel motore è spiegata per esteso.
Aggiornato ad ogni nuova decisione, non solo alla fine di una sessione.

---

## 1. Architettura generale

**Motore**: MATLAB (licenza universitaria, nessun bisogno di MATLAB Compiler/Web App
Server). Logica di business e validazione vivono in MATLAB, in `+src/+state`/`+src/+io`/
`+src/+engine`/`+src/+app` — stesso pattern a namespace-class già rodato in FantaMath.

**Frontend**: HTML/CSS/JS vero (non MATLAB App Designer/`uifigure`) — valutato e scartato
perché `uifigure` non può dare il livello grafico richiesto (niente border-radius, ombre,
hover, font custom).

**Bridge**: FastAPI (Python), stesso pattern del companion read-only già esistente in
FantaMath, esteso qui per accettare anche scritture.

**Scritture asincrone via coda file**: il web non scrive mai `lega.mat`/`lega.json`
direttamente. Ogni azione (modifica banca, bonus/malus, upload CSV, cambio parametri
formula) va in `config/leagues/<lega>/queue.json`; un poller MATLAB (`watchLeague.m`, tick
ogni 2s) la legge, applica via `LeagueState`, risalva, riesporta il JSON. Scartata
l'alternativa "MATLAB Engine API for Python" (sessione MATLAB sempre viva, dipendenza
extra) — preferita la coda perché più semplice da mantenere e coerente col companion
già esistente.

**Multi-lega**: ogni lega vive in `config/leagues/<slug>/` (proprio `lega.mat`/`lega.json`/
`queue.json`), `config/active.json` indica quale è attiva. Motivazione: l'utente vuole poter
provare parametri/modifiche senza rischiare la lega vera, o gestire più leghe reali in
parallelo.

---

## 2. Setup Lega — dati e formule

### Struttura dati (`LeagueState`)

```
meta:      schemaVersion, lastCsvPath, lastCsvLoadedAt
epsilon:   double, chiesto una volta al primo setup, mai richiesto di nuovo su aggiornamento CSV
players:   tabella intera dal CSV (id, nome, ruoli, fvm, quot, age, team, costo, owned, fuoriLista)
params:    phi, alphaF, alphaQ, pLow, pHigh (normalizzazione, vedi §4)
scores:    id, fScore, qScore, score — ricalcolati ad ogni cambio player/params
teams.table: name, creditiIniziali, bankOverride, teamValue
teams.transactions: registro bonus/malus (Timestamp, Team, Type, Amount, Motivo)
teams.released: id giocatori svincolati in sessione (non ancora usato)
```

### Banca residua — formula

```
banca_base = bankOverride se impostato, altrimenti creditiIniziali
bonusMalusSum = somma di teams.transactions.Amount per quella squadra
residuo = banca_base + bonusMalusSum   <- SEMPRE additivo
totale = residuo + teamValue
```

**Decisione (2026-08-02)**: la prima versione faceva sì che `bankOverride`, se impostato,
**sostituisse** interamente il calcolo (ignorando bonus/malus successivi) — comportamento
confuso in UI (un bonus applicato spariva se la banca era stata corretta a mano prima).
Corretto: override e bonus/malus sono sempre sommati, mai uno maschera l'altro.

### Bonus/Malus

Motivo **obbligatorio**, validato sia lato client (bottone disabilitato) sia lato MATLAB
(`FantaManager:transaction:missingMotivo`) — mai fidarsi solo del client.

---

## 3. Merge CSV (aggiornamento listone)

Chiave di match: **nome giocatore** (stringa), non l'id numerico — l'utente ha confermato
che l'id non è garantito stabile fra un'esportazione e l'altra del sito, il nome sì.

Regole:
- Solo nel CSV nuovo → inserito così com'è.
- Solo nel salvato (assente dal nuovo CSV) → tenuto, `fuoriLista=true`, nient'altro toccato.
- In entrambi → `FuoriLista, Sq., Under, R., R.MANTRA, PGv, MV, FM, FVM/1000, QUOT.,
  FantaSquadra` sempre sovrascritti col nuovo. `Costo`: nuovo se presente e diverso dal
  salvato, altrimenti tenuto il vecchio (un CSV con Costo vuoto non deve azzerare un costo
  già noto).

Dopo il merge: `teamValue` ricalcolato, squadre nuove trovate nel CSV chiedono Crediti
Iniziali prima di essere aggiunte (mai un default silenzioso).

---

## 4. Normalizzazione FVM/QUOT — formule e parametri

Analisi dettagliata completa in `docs/normalizzazione-fvm-quot.md`. Riassunto delle formule
e delle decisioni finali qui.

### Le formule esatte (`+src/+engine/normalizeScore.m`, `mixScores.m`, portate da FantaMath)

```
rawLog = log(1 + alpha * raw)
lo = percentile(rawLog, pLow*100)
hi = percentile(rawLog, pHigh*100)
score = clip((rawLog - lo) / (hi - lo), 0, 1)

S = phi * F_score + (1 - phi) * Q_score
```

`alpha` comprime la coda (valori alti "schiacciati" verso il centro prima di normalizzare).
`pLow`/`pHigh` tagliano gli estremi prima di normalizzare (winsorizing) — **sconsigliato
toccarli** (vedi sotto). `phi=1` → punteggio finale identico a F_score puro; `phi=0` →
identico a Q_score puro.

### Decisioni sui parametri (2026-08-02)

| Parametro | Valore | Perché |
|---|---|---|
| `alphaF` | **2** | Vincolo del proprietario lega: "2-3 giocatori mediani = 1 top", non di più non di meno. A αF=2, rapporto score(top)/score(mediano)=2.34 sui dati reali (313 giocatori). Testato l'intero spettro 0.00001→100.000: sotto αF=2 i top "volano" troppo (7x a αF=0.03), sopra αF=5 il rapporto scende sotto 2.2 (troppo piatto, i fenomeni perdono vantaggio). |
| `alphaQ` | **0.08** | Stesso vincolo 2-3x (rapporto 2.38). Scala diversa da alphaF perché QUOT ha range molto più piccolo (1-33 contro 1-350 di FVM) — gli `alpha` dei due parametri non sono confrontabili direttamente. |
| `pLow` | **0** (invariato) | Tagliare percentili appiattisce i top player fra loro (verificato: pHigh=0.90 schiaccia 32 giocatori diversi allo stesso punteggio 1.000) — stesso bug già trovato in FantaMath su roleDemand. Comprimere con alpha è sempre preferibile a tagliare con percentili. |
| `pHigh` | **1** (invariato) | Idem. |
| `phi` | **0.40** (QUOT 60% / FVM 40%) | Decisione del proprietario lega: FVM è più volatile (utile a differenziare, ma "vola troppo" da solo), QUOT è più stabile (quotazione di mercato) — va pesato di più il segnale stabile. Coerente con la stessa scelta già fatta nel progetto gemello FantaMath. |

### Perché non "il più simmetrico possibile"

Una distribuzione perfettamente simmetrica (alpha altissimo) cancellerebbe il vantaggio
reale dei giocatori più forti — sbagliato per il fantacalcio, dove pochi fenomeni DEVONO
valere sproporzionatamente di più. Il vincolo giusto non è statistico (skewness=0) ma
economico/di gioco: quanti giocatori di fascia inferiore servono per eguagliare uno di
fascia superiore. Prima versione di questa analisi cercava la simmetria — corretta dopo
il chiarimento del proprietario della lega.

### Limite noto, non risolto: instabilità agli estremi

`normalizeScore` ancora sempre il minimo del pool a 0.000 e il massimo a 1.000 esatti.
Rimuovere il singolo giocatore top dal pool sposta *tutti* gli altri punteggi (shift medio
0.008, massimo 0.016 sui dati reali). Un metodo alternativo (rank percentile +
curva esponenziale, dettagli in `normalizzazione-fvm-quot.md` §6c) è stato **progettato,
testato e scartato**: risolveva la stabilità ma introduceva un problema peggiore — premiava
"quanti giocatori affollati hai superato" invece del vero merito (dimostrato con dati reali:
1 punto di gap FVM in una zona affollata dava lo stesso salto di punteggio di 5 punti di gap
in una zona rada). Il metodo min-max attuale resta la scelta migliore trovata finora, con
questo limite di stabilità esplicitamente accettato, non ignorato.

---

## 5. Log decisioni cronologico

- **2026-08-02**: bootstrap progetto, scelta architettura (MATLAB+FastAPI+queue), scelta
  formato config (.mat sorgente + .json esportato, non solo .mat, per interoperabilità
  Python).
- **2026-08-02**: merge CSV chiave=nome (non id), regole di sovrascrittura per campo,
  gestione tri-stato Costo.
- **2026-08-02**: banca/bonus-malus sempre additivi, mai mascherati da override.
- **2026-08-02**: multi-lega, switch/creazione da frontend.
- **2026-08-02**: normalizzazione FVM/QUOT — vincolo "2-3 medi=1 top" (non simmetria),
  αF=2/αQ=0.08/φ=0.40, metodo rank-esponenziale scartato dopo verifica.
- **2026-08-02**: aggiunta schermata "Lista giocatori" (664 righe, ricerca nome, filtro
  ruolo, colonne ordinabili) prima di procedere a scarsità ruolo — utile per validare
  visivamente i prossimi step della pipeline (FormulaEngine: normalizza→mix→**scarsità
  ruolo**→role factor→floor→età→conversione crediti). Deciso di NON convertire ancora S in
  crediti reali: senza scarsità ruolo la classifica è distorta (es. Dimarco, terzino, sopra
  ogni centrocampista) — convertirla in crediti ora cristallizzerebbe quella distorsione in
  un valore economico reale.

- **2026-08-02**: scarsità ruolo (`roleDemand`/`roleScarcity`/`roleFactor`, portati da
  FantaMath) collegati a `LeagueState.recomputeScores`. Parametri: `qw=1` (penalizza panchine
  senza essere estremo — verificato: la maggior parte dei ruoli ha pochi giocatori scarsi tra
  i posseduti, eccetto Por con 25% di riserve), `eta=1` (lineare), `mixOwned=1` (solo
  posseduti), `nmax=3`/`beta=0.2` (bonus duttilità multi-ruolo, scelto da Claude su richiesta
  esplicita). Verificato sui dati reali: Dc/M/Por più scarsi, C/T più abbondanti, B
  (Braccetto) ora scarso come atteso dalla fix di roleDemand. RoleFactor dipende solo dal
  ruolo (non dalla qualità del giocatore) — per design, la differenziazione per bravura resta
  in S, si combinano nel prossimo step (`assembleWeight`, non ancora costruito).
- **2026-08-02**: testata anteprima S×PesoRuolo (rho=1) — overcorrezione, Martinez L.
  (S=0.992, il migliore) sparisce dalla top 20, dominano Dc/M con S mediocre ma RoleFactor
  alto. **Confermato dal proprietario della lega**: il valore deve venire principalmente
  dalla forza del giocatore (S), la scarsità di ruolo deve attenuare/aggiustare, non
  ribaltare la classifica. Prossima sessione: abbassare `rho` (provare 0.3-0.5) quando si
  costruisce `assembleWeight` vero, non un semplice prodotto S×PesoRuolo.
- **Prossimo**: età (`ageWeight`), poi floor, poi conversione finale in crediti
  (`assembleWeight`→`auctionPrice`/`releaseValue`, con `rho` basso per non far dominare il
  ruolo sulla forza del giocatore).

*(continua ad ogni nuova decisione)*

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
- **2026-08-03**: `rho` non ancora deciso da modificare — il proprietario lega ha scelto
  invece di esporre `roleOverride` (già presente in `roleFactor.m` come knob non ancora
  raggiungibile da UI) in una pagina dedicata "Ruoli" (navbar), con un moltiplicatore
  manuale editabile per ognuno dei 12 ruoli Mantra, applicato PRIMA del MAX in `roleFactor`.
  Default di tutti i 12 = 1.0 (nessun cambiamento ai punteggi attuali, esplicitamente
  richiesto — la valutazione dei valori resta manuale, decisa dal proprietario). Aggiunto
  `LeagueState.setRoleOverride` (valida tutti e 12 i token presenti, ognuno > 0) e azione
  coda `setRoleOverride`. La colonna "Consigliato" mostrata in UI è solo di riferimento
  (mai applicata in automatico): calcolata dal `ScarNorm` reale per ruolo (ricavato da
  `roleDemand`+`roleScarcity` sui dati della lega attiva) con una piccola spinta (+0.35 ×
  quanto il ruolo è sotto scarsità media) solo sui ruoli puramente offensivi abbondanti
  (E, W, T, Pc) — richiesta esplicita: "gli attaccanti sono quelli con più bonus, ruoli
  offensivi prima", ma "pesato leggermente", non un ribaltamento come il semplice
  S×PesoRuolo con rho=1 già scartato in precedenza.
- **2026-08-03 (correzione)**: la prima versione della colonna "Consigliato" era hardcoded
  nel frontend (numeri statici scritti a mano, presi da un calcolo offline una tantum) —
  il proprietario ha fatto notare correttamente che non usava davvero la formula/i dati
  reali della lega. Corretto: `LeagueState.recomputeScores` ora calcola anche
  `state.roleSuggestion` (per ognuno dei 12 token: `scarNorm` reale da
  `roleScarcity.ScarNorm`, `recommended` = stessa regola di prima ma dal valore live),
  esportato in `lega.json`. Il frontend legge `state.roleSuggestion`, niente più numeri
  statici — cambia automaticamente se cambiano listone/rose/parametri scarsità.
- **2026-08-03 (seconda correzione, definitiva per ora)**: anche la versione "ScarNorm +
  bump offensivo" era sbagliata — il proprietario ha fatto notare che ScarNorm (conteggio
  teste demand/supply) non risponde alla vera domanda per lo svincolo: "se perdo questo
  giocatore, quanto sono peggiori le alternative libere rimaste?". Verificato sui dati
  reali: Por ha lo svincolo più critico di tutti (11 portieri con FVM≥20 su 67, **tutti già
  posseduti, zero liberi**) — ScarNorm da solo non lo segnalava. Sostituito con una metrica
  diretta: per ogni ruolo, gap% = (FVM medio posseduti − FVM medio liberi) / FVM medio
  posseduti × 100 (normalizzato per scala, così portieri e attaccanti sono confrontabili
  nonostante FVM assoluti molto diversi). `recommended` = min-max di gap% su tutti i 12
  ruoli, mappato su [1.00, 1.20] (tetto esplicito del proprietario) — il ruolo con gap%
  minimo (B, 40%) = 1.00, quello con gap% massimo (Por, 95%) = 1.20, ogni ruolo il suo
  valore individuale ("ogni ruolo proprio mod", non più tier condivisi). Implementato in
  `LeagueState.computeRoleSuggestion` (ora prende anche `players`, non solo `scarcity`).
  Pagina "Ruoli" estesa con tabella completa (posseduti/liberi/FVM/gap%/ScarNorm) e due
  grafici a barre (disponibilità per ruolo, gap% per ruolo) per decidere con i dati davanti,
  non alla cieca.
- **2026-08-03 (bug fix + correzione di rotta)**: trovato bug pre-esistente (non di questa
  sessione): l'azione coda `setRoleParams` (controlla `rho`/`qw`/`eta`/`nmax`/`beta`) non era
  mai stata collegata in `processQueue.m` — solo `setRoleOverride` lo era. Ogni tentativo di
  cambiare `rho` da remoto/web falliva silenziosamente ("Tipo azione sconosciuto"), motivo
  per cui `rho` è rimasto a 1 dall'inizio nonostante l'HANDOFF dicesse di abbassarlo.
  Aggiunto il case mancante, testato (`tProcessQueueTest`). **Nessun valore applicato**:
  `rho` resta 1, `roleOverride` tutti 1.0 — il proprietario ha corretto un tentativo di
  applicare in automatico i valori "Consigliato" (gap%) come modificatore reale: quei
  numeri sono **solo indicativi**, il modificatore lo decide e digita sempre lui a mano,
  mai auto-applicato da Claude.
- **2026-08-03 (formula assembleWeight, prima parte)**: deciso `valore = S × (1 + mod +
  duttilità + età + ...)` — additivo puro, non `(1+mod+duttilità) × (1+età)`. Motivo:
  con l'additivo il tetto massimo teorico è sempre la somma dei tetti singoli (prevedibile,
  facile da spiegare), col moltiplicativo ogni bonus amplifica gli altri e il massimo reale
  cresce ad ogni nuovo termine aggiunto (stesso tipo di rischio di "ribaltamento" già visto
  con `rho=1`). `mod` = il modificatore che il proprietario scrive a mano nella pagina Ruoli
  (`roleOverride - 1`, quindi 0 se override=1.00, +0.20 se override=1.20) — **non
  moltiplicato per ScarNorm**, coerente con la correzione precedente (scarsità solo
  indicativa). `floorValue` (prossimo step dopo età) probabilmente NON entra in questa
  somma: è un minimo assoluto, va applicato come clamp finale dopo, non come termine
  percentuale — da confermare quando ci si arriva.
- **2026-08-03 (bug fix Flex + parametri duttilità)**: la vecchia `Flex = 1 + beta ×
  log(1+nRoli)/log(1+nmax)` (beta=0.2, nmax=3) dava già +10% a **chi ha un solo ruolo**
  (bug, doveva essere 0%). Sostituita con tabella diretta a parametri modificabili: 1
  ruolo → Flex=1.00, 2 ruoli → `1+duttilita2` (default 0.03), ≥nmax ruoli → `1+duttilita3`
  (default 0.05). Nuovo setter `LeagueState.setDuttilita` + azione coda `setDuttilita`.
  Il vecchio `beta` resta nello stato salvato di legiche pre-esistenti ma non è più letto
  da nessuna formula (harmless leftover, non pulito per non toccare `.mat` già salvati).
- **2026-08-03 (peso età, `ageWeight`)**: prima versione a step fissi (soglie 23/31,
  bonus/malus 5%/5%, ripresi dal vecchio FantaMath) **sostituita** su richiesta esplicita
  del proprietario con una rampa lineare, solo bonus giovani, mai malus/negativo:
  `bonus = etaBonusMax` per età ≤ `etaFloor` (15, età minima Serie A — non ha senso premiare
  ancora di più sotto quella soglia), scende linearmente a 0 a `etaZero` (38), resta a 0
  sopra. Default: `etaFloor=15, etaZero=38, etaBonusMax=0.10`. Nuova colonna
  `state.scores.etaWeight`, nuovo motore `+src/+engine/ageWeight.m`, setter
  `LeagueState.setEtaParams` (arity cambiata, non più 4 parametri soglie ma 3: floor/zero/
  bonusMax), azione coda `setEtaParams` aggiornata di conseguenza. Pagina "Età" (navbar)
  aggiunta con grafico a serie (linea, non barre — dati reali FVM medio posseduti/liberi per
  età) e soglie marcate, per studiare la curva prima di scegliere i parametri — nessun
  valore applicato in automatico, sempre a scelta manuale del proprietario.
- **2026-08-03/04 (analisi storica, non applicata)**: analizzato un export storico
  (`FantaExport_04022026.xlsx`, 318 giocatori) di una vecchia lega dove lo svincolo era
  stato accettato come corretto. Regressione: `Svincolo ≈ 0.35 + 0.341×FVM + 1.145×Quot`
  (lineare diretto su FVM/QUOT grezzi, non normalizzati/compressi) spiega già il 94.9%
  della varianza. Aggiungendo una **minusvalenza** (confermata dal proprietario: se il
  costo pagato all'asta supera il valore stimato dalle statistiche, recupera il ~15% della
  differenza: `svincolo_finale = svincolo_stat + 0.15×max(0, costo-svincolo_stat)`) il fit
  sale a R²=0.977, quasi esatto anche su outlier come Dybala (svincolo reale 39, stimato
  solo-stat 26.2, con minusvalenza 37.1). Il vecchio sistema era quindi molto più semplice
  dello stack attuale (S/roleFactor/duttilità/età/esponente k). **Decisione: tenere lo
  stack attuale così com'è**, non sostituirlo col modello lineare né aggiungere la
  minusvalenza per ora — analisi tenuta come riferimento se in futuro i valori finali
  sembrano fuori scala rispetto allo storico accettato dalla lega.
- **2026-08-04 (assembleWeight costruito per davvero)**: fino a qui `S×(1+mod+dutt+eta)`
  esisteva solo in script Python fuori da MATLAB — la Lista Giocatori nell'app mostrava
  ancora `RoleFactor`/`PesoRuolo` (vecchia pipeline moltiplicativa, `rho=1`, scarsità sempre
  nel calcolo), causa di confusione: Kalulu (difensore, ruolo scarso) restava in cima anche
  con `override=1` perché quella pipeline non era mai stata spenta. Costruito per davvero:
  nuovo `src/engine/roleMod.m` (mod diretto da `roleOverride`, MAX tra i ruoli del
  giocatore, **non** moltiplicato per ScarNorm) e `src/engine/assembleWeight.m`
  (`S.*(1+mod+duttilita+eta)`, additivo puro). Nuove colonne `state.scores.mod` e
  `state.scores.assembleWeight`. RoleFactor/PesoRuolo **non rimossi** (restano per
  retrocompatibilità e per calcolare ScarNorm/Consigliato nella pagina Ruoli) ma la Lista
  Giocatori ora mostra ed ordina di default su `assembleWeight`, non più su `pesoRuolo`.
  Verificato: Martinez L. assembleWeight=1.035, Kalulu=0.669 — ordine corretto.
- **2026-08-04 (conversione finale in crediti, `auctionPrice`)**: testate e scartate
  sigmoide (schiaccia troppo la cima, errore 12× peggiore della potenza sui percentili
  storici) e distribuzione gaussiana (matematicamente incompatibile: con media fissa =
  budget/N, un top di 90-130 manda 25-33% del roster sotto zero prima del floor, sforando il
  budget del 20-46%). FVM/QUOT grezzi verificati log-normali/power-law (skewness log quasi
  zero, corr(log rank, log valore) ≈ -0.88/-0.81) — la potenza non è arbitraria, ricostruisce
  la forma naturale che la normalizzazione percentile aveva compresso via. Un esponente
  puro (`assembleWeight^k`) crea però un problema nuovo: per portare il top a 100-150 serve
  k alto (2.6-3.3), che schiaccia 53-92 giocatori "reali ma mediocri" (non i 7 veri-zero)
  nella stessa fascia bassa. Risolto con un **offset prima della potenza**:
  `credito = (assembleWeight + offsetC)^expK`, riscalato al budget lega (`sum(creditiIniziali)
  × (1+epsilon)`, calcolato solo sui posseduti), floor finale come clamp di sicurezza.
  Grid-search sui dati reali: **offsetC=0.52, expK=4.5, floor=1** porta il top a ~100.8 e
  dimezza l'ammassamento in fondo (nessuna fascia da 5 crediti sopra 84 giocatori, contro
  144 del tentativo precedente). Implementato in `src/engine/auctionPrice.m`, nuova colonna
  `state.scores.creditoStimato`, setter `LeagueState.setAuctionParams`, azione coda
  `setAuctionParams`. Pannello parametri (offsetC/expK/floor) aggiunto in cima alla Lista
  Giocatori, che ora ordina di default su `creditoStimato`. Verificato in produzione:
  Martinez L.=100.8, somma posseduti=5728.9 (budget 5727).

- **2026-08-04 (tasse svincolo)**: trovato precedente reale in un altro branch mai
  merge-ato (`raw_data/FantaMath`, fase "tassazione-svincolo-e-export"): `releaseTax.m`
  con `TassaValore` (aliquota su tutto il valore, diversa per motivo estero/decisionale) +
  `TassaPlusvalenza` (separata, solo sul guadagno) — struttura ripresa. **Nessun recupero
  minusvalenza** in quel codice originale (esplicitamente escluso); aggiunto qui su
  richiesta esplicita del proprietario. Valori scelti (non tarati sui dati, decisione
  libera): `taxEstero=0, taxDecisionale=0.15, taxPlusvalenza=0.10,
  taxMinusvalenza=0.15 (recupero), taxFee=0`. Nuova colonna
  `state.scores.incassoNettoDecisionale` (anteprima assumendo sempre motivo decisionale,
  il più comune). Implementato: `src/engine/releaseTax.m`, setter
  `LeagueState.setTaxParams`, azione coda `setTaxParams`, pagina "Tasse" (navbar).
  Verificato: se tutti i 313 posseduti si svincolassero ora (decisionale), lordo totale
  5728.9 → netto 4901.8 (calo 14.4%).

- **2026-08-04 (invariante W* sul netto, non sul lordo)**: correzione importante —
  l'invariante "somma = budget lega" va sul **netto** (dopo tasse, motivo decisionale), non
  sul lordo (`creditoStimato`). Richiesta esplicita: "se tutti svincolano tutti abbiamo
  W* = crediti iniziali × (1+epsilon)", nonostante le tasse. `epsilon` scarterebbe (scala
  tutto proporzionalmente, non fissa il rapporto top/resto) — motivo la doc precedente
  raccomandava `expK`/`offsetC` per la forma, ma quei parametri da soli restano tarati sul
  lordo, non compensano la perdita media da tassazione. Risolto con bisezione in
  `recomputeScores`: trovo lo scale-factor `s` tale che
  `sum(releaseTax(s×shape, costo, decisionale).IncassoNetto)` sui posseduti sia esatto a
  `totalBudget` (funzione monotona in `s`, bisezione converge in poche decine di iterazioni).
  Il lordo (`creditoStimato`) diventa quindi conseguenza del netto, non il contrario — sale
  automaticamente per compensare la tassa media, invece di dover essere ritarato a mano
  (`offsetC`/`expK` restano fissi e controllano solo la FORMA, non più la scala assoluta).
  Verificato: budget W*=5727.0, netto totale=5727.0 esatto, lordo totale sale a 6852.5,
  Martinez L. lordo=120.6 → netto=106.8.

- **Prossima sessione (da fare)**: tuner serio per la conversione crediti — l'utente imposta
  il "top netto" desiderato (es. 150) e il sistema calcola `auctionExpK` da solo via
  bisezione (stesso principio già usato per l'invariante W* sul netto), invece di tarare
  `expK` a tentativi come fatto oggi (5.5→135, 6.0→153, trovati a mano). Aggiungere anche
  grafici seri (serie/istogrammi, non solo tabelle numeriche) su tutte le pagine con
  parametri modificabili: Ruoli, Età, Tasse, Conversione crediti — per capire l'effetto
  visivamente prima di salvare, non solo leggere numeri in tabella.

- **2026-08-05 (Lista giocatori: fix filtro multi-ruolo, filtro fuori-lista/estero,
  crediti arrotondati)**: tre richieste esplicite del proprietario.
  1. Bug filtro multi-ruolo "non si vede": le pill ruolo usavano `classList.add("btn-primary")`
     senza togliere `btn-ghost` — a parità di specificità CSS `.btn-ghost` è dichiarata dopo
     `.btn-primary` in `styles.css` e vinceva sempre, quindi il click non cambiava aspetto
     (il filtro funzionava, ma sembrava non fare nulla). Fix: swap esplicito delle classi
     in `app.js` (`renderPlayerList`).
  2. Filtro "Possesso" aveva solo Tutti/Solo posseduti/Solo svincolati, e "svincolati"
     includeva anche i fuori-lista (owned=false li esclude ma non era un'opzione dedicata).
     Aggiunta quarta opzione "Fuori lista / estero" (`filterOwned === "fuorilista"`),
     "Solo svincolati" ora esclude esplicitamente i fuori-lista.
  3. Tutti i valori in crediti (costo, credito stimato/lordo, netto svincolo, plus/minus,
     valore titolari formazione) mostrati **interi, arrotondati per eccesso** (`Math.ceil`
     lato frontend, `math.ceil` lato export xlsx) — mai più decimali su numeri in crediti.
     Nuovo helper `fmtCredit()` in `app.js`. I punteggi non-crediti (Valore/assembleWeight,
     mod, duttilità, età, F/Q score) restano a 3 decimali, non toccati.

- **2026-08-05 (export xlsx: solo Ruolo Mantra + Netto svincolo + Valore assoluto)**:
  tolte dal file `/api/export-listone` le colonne Ruolo (classico) e Credito stimato
  (lordo) — richiesta esplicita "solo ruolo mantra e valore svincolo (netto) senza dire
  il lordo". Aggiunta colonna "Valore" = `assembleWeight` (lo stesso "valore assoluto"
  mostrato in Lista giocatori), su richiesta esplicita per avere un riferimento di valore
  intrinseco del giocatore indipendente dal netto post-tasse. Netto svincolo arrotondato
  per eccesso nel file. Implementato in `server/main.py` (`export_listone`).

- **2026-08-05 (scraper mercato in scripts/, dati in docs/data/)**: richiesta esplicita
  del proprietario di aggregare dati di mercato da fantacalcio.it (quotazioni/FVM
  ufficiali + commento PRO/CONTRO per giocatore), FantaGoat (performance/titolarità/
  continuità + multi-stagione) e FantaLab (guida asta, rosa Hoffenaimer sincronizzata
  con rating) per preparare l'asta di riparazione. Decisioni tecniche:
  - fantacalcio.it è server-rendered e pubblico (nessun login richiesto) — scraper con
    `requests`+`BeautifulSoup`, niente browser headless. Verificato: 494 giocatori
    dal listone ufficiale 2026/27 in un'unica richiesta (i dati sono negli attributi
    `data-filter-*`/`data-col-key` delle righe tabella, non serve JS).
  - FantaGoat/FantaLab sono SPA con login — **niente automazione del login**: lo
    script `scrape_login.py` apre un browser vero, il proprietario fa login a mano,
    lo script salva solo cookie/localStorage in `config/scrape_sessions/*.json`
    (cartella già in `.gitignore`, mai vista da git). Motivo: entrare credenziali
    per conto dell'utente è vietato dalle regole di sicurezza dell'agente, a
    prescindere da chi lo chiede.
  - `scripts/scrape_fantagoat.py` e `scrape_fantalab.py` sono scritti sulla struttura
    DOM osservata a mano durante l'analisi rosa Hoffenaimer, ma **non testati
    end-to-end** (serve la sessione reale per farlo): possibile che qualche
    selettore vada corretto alla prima esecuzione vera.
  - Output sempre in `docs/data/*.csv`, mai nel repo committato senza controllo
    (dati di terzi, verificare licenza/ToS prima di condividere pubblicamente).

- **2026-08-05 (W\* sottrae la banca residua, non solo crediti iniziali)**: il proprietario
  ha notato che dando un bonus di 850 crediti a una squadra, il netto svincolo dei
  giocatori non si muoveva — la formula ignorava banca/bonus/malus del tutto
  (`totalBudget = Σ creditiIniziali · (1+epsilon)`, fisso). Bug concettuale: un bonus
  inietta ricchezza nel `residuo` di quella squadra ma il pool usato per scalare il valore
  netto di TUTTI i giocatori di lega restava invariato — la stessa ricchezza finiva
  contata due volte (banca + valore giocatori) senza che nessuno dei due si riducesse.
  Corretto: `totalBudget = Σ creditiIniziali · (1+epsilon) − Σ residuo(squadra)`, dove
  `residuo` (banca + bonus/malus, sempre additivo, §"Banca residua" sopra) è ora sottratto
  dal pool. Riusa `bankResiduoVector` già esistente, nessuna nuova funzione.
  **Limite noto, accettato esplicitamente dal proprietario**: la banca è tracciata a mano
  (`bankOverride`), non derivata automaticamente da `creditiIniziali − costi pagati` — se
  la banca inserita diverge da quanto realmente speso, l'invariante diverge di
  conseguenza. Non risolto in questa sessione, solo segnalato.
  Implementato: `+src/+state/LeagueState.m` (`recomputeScores`). Test aggiornati:
  `tAuctionPriceTest.stateScoresHasCreditoStimatoColumn`,
  `tLeagueStateCsvTest.createFromCsvBuildsTeamsWithValueAndCredits` (stessa formula,
  prima non includevano la sottrazione). Suite completa: 74/74 pass dopo la modifica.

- **2026-08-07 (`auctionExpK`: 4.5 → 2.5, ricalibrazione)**: `expK=4.5` era stato scelto
  guardando solo la forma della distribuzione crediti (spread, no ammassamento in fondo —
  vedi voce 2026-08-04 "conversione finale in crediti"), mai verificato contro un
  riferimento di mercato oggettivo. Trovato il problema analizzando la rosa Hoffenaimer:
  quotazione/FVM aggregati più alti di tutta la lega (337/1450, 1° su 10) ma valore
  calcolato solo 7°/10 — sintomo di un esponente troppo aggressivo che premia il singolo
  fenomeno più della ricchezza aggregata della rosa. Verificato su tutte e 10 le squadre:
  a `expK=4.5` `corr(quotazione, valore)=0.40`, a `expK=2.0–2.5` sale a `0.87–0.89` (miglior
  fit), mantenendo comunque una correlazione positiva col miglior giocatore singolo (non
  annullando il premio fenomeno, solo riportandolo in scala). Effetto sui 295 giocatori
  posseduti: i 14 top (`assembleWeight≥0.6`) perdono in media −48.6% (Martinez L./Malen,
  i due più estremi, −64% ciascuno), i restanti 281 guadagnano, concentrato soprattutto
  nelle fasce medio/basse (+20/+72% medio) — la torta totale lega resta quasi invariata
  (5401→5404), è una redistribuzione interna, non un'inflazione. Cambiato dall'interfaccia
  (pagina "Conversione crediti", non da codice). Nessun altro parametro toccato in questa
  sessione (`roleOverride` resta neutro a 1.0 su tutti i ruoli, tasse invariate).

- **2026-08-07 (`auctionExpK` 2.5 → 0.95, `auctionOffsetC` 0.52 → 0, seconda ricalibrazione
  nella stessa giornata)**: il proprietario ha posto tre vincoli espliciti sul risultato
  finale: il top della lega (Martinez L., aWeight=1.039) deve valere circa 100 crediti, Kean
  (il suo miglior giocatore) 70-80, la distribuzione non deve essere troppo compatta/ammassata
  in fascia media. Testate sistematicamente 13 famiglie di formula (esponenziali a più
  intensità, lineare, radice, logaritmiche, ibride lineare+potenza, sigmoidi), poi affinato
  con una grid search fine sull'esponente (`k*aw^p`, `p` da 0.80 a 1.50): `p=0.95` è il punto
  che centra entrambi i target (Martinez=101.9, Kean=76.7) con la correlazione più alta con
  la quotazione di mercato oggettiva tra le formule che rispettano i target (r=0.966) e quasi
  dimezza l'ammassamento rispetto a `expK=2.5` (87 vs 141 giocatori in banda 5 crediti).
  **Contro-argomento ricevuto da un consiglio di AI esterne** (query al provider Antigravity,
  modalità agent-enhanced): proponeva di andare nella direzione opposta, esponente convesso
  `p=1.25-1.40`, sostenendo che la convessità avrebbe "cancellato" le compressioni a monte
  (log della pipeline normalizeScore + tassazione svincolo) riducendo l'ammassamento.
  **Verificato empiricamente sui 295 giocatori reali e confutato**: l'ammassamento resta
  piatto (85-91) su tutto il range 0.90-1.50, non scende affatto salendo con `p` come previsto
  dall'argomento teorico; nel frattempo Martinez/Kean sforano i target sopra `p=1.1` e la
  correlazione mercato peggiora costantemente (0.97 a p=0.90 → 0.83 a p=1.50). Il
  ragionamento del consiglio era analiticamente plausibile ma non verificato sui dati reali di
  questa lega, motivo per cui è stato scartato solo dopo verifica numerica indipendente, non
  per fiducia/sfiducia aprioristica nella fonte. Eseguiti anche due controlli di robustezza
  richiesti dal consiglio: stress test su acquisti sbagliati in asta (aWeight basso, costo
  pagato alto) — il recupero minusvalenza del 15% non genera netti sproporzionati; audit
  inversioni di ranking — 1487 coppie su 43365 (3.4%) hanno un giocatore a aWeight più basso
  che vale più crediti di uno a aWeight più alto, dovuto al meccanismo fiscale su
  plus/minusvalenza rispetto al costo pagato in asta, quota giudicata fisiologica.
  **Limite noto, segnalato dal consiglio e non risolto**: l'esponente `p=0.95` è stato
  scelto per centrare i valori di due soli giocatori (Martinez L. e Kean) — i loro netti
  dipendono anche dal costo pagato storico via le tasse, quindi se il listone FVM/QUOT
  cambiasse sensibilmente per questi due, la calibrazione andrebbe rifatta, non è un punto
  fisso strutturale della lega. Applicato in coda azioni (`setAuctionParams`,
  `offsetC=0, expK=0.95, floorCredito=1`), non ancora processato da `watchLeague.m` al momento
  della scrittura (nessuna istanza MATLAB/server attiva) — resta "pending" in
  `config/leagues/mantramanager/queue.json` finché l'app non viene rilanciata.

*(continua ad ogni nuova decisione)*

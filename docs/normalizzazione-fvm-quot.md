# Normalizzazione FVM/QUOT — analisi e scelte

Data: 2026-08-02
Dataset analizzato: 313 giocatori posseduti (lega reale, listone caricato in FantaManager)

## Perché questo documento

I parametri `alphaF`, `alphaQ`, `pLow`, `pHigh`, `phi` (pannello "Formula valori" →
Normalizzazione FVM/QUOT) sembrano astratti finché non si vede il loro effetto sui dati
reali. Questo documento registra l'analisi fatta sui 313 giocatori posseduti della lega
caricata, i numeri trovati, e **perché** sono state scelte queste impostazioni — non solo
quali.

## 1. I dati grezzi

```
FVM:  mediana 15, p90=82, p95=100, p99=270, max=350   (p99/mediana = 18x)
QUOT: mediana 10, p90=18, p95=23, p99=27, max=33      (p99/mediana = 2.7x)
```

FVM ha una coda lunghissima: pochi giocatori-fenomeno con proiezione molto alta, la
stragrande maggioranza bassa. QUOT è già naturalmente compatto — è una quotazione
convenzionale (di solito preseason/mercato), non ha lo stesso squilibrio.

## 2. Metodo

Per ogni valore di `alpha` testato, si calcola `normalizeScore` esattamente come fa
`+src/+engine/normalizeScore.m` (`log(1+alpha*raw)`, poi min-max su tutto il pool, `pLow=0`/
`pHigh=1`), e si misura:

- **media**, **deviazione standard**: quanto è ampia la distribuzione
- **asimmetria (skewness)**: 0 = simmetrica, positiva = coda a destra (molti bassi, pochi
  alti), negativa = coda a sinistra (molti alti, pochi bassi)

Sweep fatto su `alpha` da 0.00001 a 100.000 (scala logaritmica), sia per FVM che per QUOT,
sui dati reali via API (`/api/state`).

## 3. Il vincolo vero: non simmetria, ma "2-3 medi valgono 1 top"

Prima analisi di questo documento cercava la minima asimmetria statistica. **Scartata**: il
proprietario della lega ha chiarito il vincolo reale — non vuole i top player "volare
troppo", ma vuole che **2-3 giocatori mediani sommati valgano circa 1 top**, 2-3 bassi
valgano circa 1 mediano, 2-3 scarsi valgano circa 1 basso. Un valore troppo simmetrico
(`alphaF≥100`) avrebbe cancellato del tutto il vantaggio dei fenomeni; un valore troppo
basso (vicino al default 0.03) li fa invece "volare" troppo (rapporto 7x rispetto al
mediano). Il punto giusto sta in mezzo, misurato direttamente sul rapporto
`score(top)/score(mediano)`, non sull'asimmetria statistica.

### FVM

```
alphaF   score_top   score_mediano   rapporto (n. medi per 1 top)
0.03     1.000       0.142           7.05   <- troppo pochi bastano, i top volano
0.5      1.000       0.364           2.75
1        1.000       0.402           2.49
2        1.000       0.428           2.34   <- scelto
3        1.000       0.438           2.28
5        1.000       0.447           2.24
8        1.000       0.453           2.21   <- valore scartato dalla prima versione
100      1.000       0.462           2.17   <- troppo piatto, cancella il vantaggio dei top
```

**Scelta: αF = 2.** Rapporto 2.34 — dentro la banda 2-3x voluta. Oltre αF=5 il rapporto
scende sotto 2.2, sempre più vicino a "2 soli mediani bastano per 1 top": troppo poco, i
fenomeni perderebbero il loro vantaggio reale. αF=2 è il punto più alto nella banda voluta,
preferito a valori più bassi (es. αF=0.5, rapporto 2.75) perché comprime comunque di più la
massa di giocatori medio-bassi, evitando che restino tutti schiacciati vicino a zero.

### QUOT

```
alphaQ    score_top   score_mediano   rapporto
0.0005    1.000       0.283           3.54   <- default precedente, troppo estremo
0.05      1.000       0.385           2.60
0.08      1.000       0.420           2.38   <- scelto
0.1       1.000       0.439           2.28
0.2       1.000       0.496           2.01   <- troppo piatto
```

**Scelta: αQ = 0.08.** Stesso ragionamento di FVM, stessa banda 2-3x (rapporto 2.38). QUOT
parte già più compatto di FVM (non ha la stessa coda estrema), quindi arriva alla banda
voluta con un `alpha` molto più piccolo in valore assoluto — la scala di `alpha` dipende
dalla scala dei dati grezzi (QUOT è 1-33, FVM è 1-350), non è direttamente confrontabile fra
i due parametri.

## 5. Taglio percentile (pLow/pHigh)

Testato l'effetto di abbassare `pHigh` invece di alzare `alphaF` (a parità di αF=0.03):

```
pHigh=1.00: skew=1.80, 1 giocatore saturato a punteggio 1.000
pHigh=0.98: skew=1.61, 7 giocatori saturati a punteggio 1.000
pHigh=0.90: skew=0.95, 32 giocatori saturati a punteggio 1.000
```

Tagliare i percentili riduce l'asimmetria ma **appiattisce i top player fra loro** (32
giocatori diversi finiscono tutti a punteggio identico 1.000 con `pHigh=0.90`) — esattamente
il bug già trovato e corretto nel progetto gemello FantaMath (`roleDemand`/normalizzazione,
handoff 2026-08-02). Comprimere con `alpha` invece di tagliare con i percentili preserva
l'ordinamento relativo fra tutti i giocatori, anche i più forti.

**Scelta: pLow=0, pHigh=1 (nessun taglio), invariati.**

## 6. Peso FVM/QUOT (phi)

Deciso direttamente dal proprietario della lega, con motivazione precisa: **FVM "vola
troppo"** (proiezione più volatile, ma utile perché differenzia bene i giocatori) mentre
**QUOT è più stabile** (quotazione di mercato/reputazione, meno soggetta a strappi). Va
quindi pesato di più il segnale stabile.

**Scelta: phi = 0.40 (QUOT 60% / FVM 40%).** Coerente con la scelta già fatta nel progetto
gemello FantaMath per lo stesso motivo. Non è una scelta statistica ma di lega — registrata
qui perché guida come i due segnali si bilanciano nel punteggio finale S.

## 6b. Instabilità agli estremi — trovata, indagata, in parte irrisolta

Osservazione del proprietario della lega: la forma "vicina a normale" di F_score (asimmetria
0.17 con αF=2) nasconde un problema. `normalizeScore` ancora **sempre** il minimo a 0.000 e
il massimo a 1.000 esatti — solo la forma in mezzo cambia con `alpha`. Con i dati reali:

```
FVM=1: 8 giocatori (probabili riserve senza dati reali) -> fanno da pavimento per tutti i 313
FVM=350: 1 solo giocatore (Malen) -> fa da soffitto per tutti i 313
```

Test di stabilità: rimuovendo il singolo giocatore top dal pool e ricalcolando, quanto si
spostano gli altri 312 punteggi?

```
min-max (metodo attuale): shift medio 0.008, shift massimo 0.016 (1.6%)
```

Non enorme, ma reale: aggiungere o perdere un solo giocatore-fenomeno (o una riserva a
FVM=1) sposta *tutti* gli altri punteggi della lega, anche chi non c'entra nulla con quel
giocatore.

**Percentile-cut mirato (testato, scartato)**: tagliare solo il fondo (`pLow=0.03`) per
escludere le 8 riserve FVM=1 dall'ancora minima. Risultato: **peggiora** il vincolo
principale (rapporto top/mediano sale da 2.34 a 4.01) — spostare l'ancora comprime la fascia
mediana più del previsto. Scartato.

**Normalizzazione robusta (mediana/MAD, testata)**: invece di ancorare a min/max letterali,
ancorare a mediana e MAD (deviazione assoluta mediana, statistica robusta agli outlier).
Stabilità: shift medio **0.000**, shift massimo **0.000** rimuovendo il top player — risolve
il problema di stabilità. Ma con clipping ingenuo a [0,1] ricrea lo stesso bug del taglio
percentile: **14-85 giocatori diversi finiscono schiacciati allo stesso punteggio 1.000**
(a seconda di quanto largo il range scelto). Serve un mapping più curato per usarla davvero,
non fatto in questa sessione.

**Conclusione**: l'instabilità agli estremi resta un limite noto e non risolto del metodo
min-max attuale. Non si sistema da sola con lavoro futuro su altri assi (es. scarsità ruolo,
che è un problema indipendente). Un fix vero richiede un metodo di normalizzazione diverso,
progettato con cura per evitare sia l'instabilità sia lo schiacciamento — lavoro dedicato,
non fatto oggi.

## 6c. Tentativo di risolvere ENTRAMBI i vincoli insieme (scalini 2-3x consistenti + stabilità)

Richiesta successiva del proprietario della lega: non solo top/mediano a 2-3x, ma **ogni
scalino** (scarso→basso→medio→top) coerente a 2-3x, sistema scalabile, equilibrato — non
concentrare credito su pochi giocatori.

**Metodo progettato**: invece di normalizzare il valore grezzo (FVM/QUOT), si usa il
**rank percentile** di ogni giocatore nel pool (posizione relativa, non valore assoluto), poi
si applica una curva esponenziale calibrata: `score = exp(b * (rank - 0.5))`, con `b`
scelto in modo che ogni scalino di 0.25 di rank percentile (un quarto del pool) valga
esattamente il rapporto voluto (qui calibrato a 2.5x, centro della banda 2-3).

Perché una curva esponenziale sul rank: è l'unica forma matematica che garantisce lo STESSO
rapporto ad ogni scalino per costruzione, non per aggiustamento manuale scalino per scalino.

**Risultato sui dati reali (quartili scarso/basso/medio/top)**:

```
scarso -> basso: 2.62x
basso  -> medio: 2.37x
medio  -> top:   2.53x
scarso -> top (salto totale): 15.7x
```

Tutti e tre gli scalini dentro banda 2-3x, per costruzione — obiettivo raggiunto.

**Ma la stabilità agli estremi PEGGIORA con questo metodo**, non migliora: rimuovendo il
singolo top player, shift medio **0.0147** (quasi 2x peggio del metodo attuale) e shift
massimo **0.073** (4.5x peggio). Motivo: il rank percentile di ogni giocatore dipende dalla
dimensione del pool (`n`) — quando un giocatore esce, il denominatore `n-1` cambia per
tutti, e la curva esponenziale amplifica questo spostamento vicino al top, dove la curva è
più ripida.

**Conclusione onesta**: nessuno dei due metodi testati oggi risolve *entrambi* i problemi
insieme. Il metodo min-max+alpha (attuale, con αF=2/αQ=0.08) è ragionevolmente stabile ma
richiede tarare ogni scalino a mano. Il metodo rank-esponenziale garantisce scalini 2-3x
consistenti per costruzione ma è meno stabile agli estremi. Una vera soluzione a entrambi
richiederebbe ancorare i percentili a un riferimento fisso esterno al pool corrente (es. una
distribuzione storica multi-stagione), non al listone della singola settimana — lavoro
architetturale più grande, da pianificare a parte, non fatto oggi.

## 6d. Verdetto finale sul metodo rank-esponenziale: scartato

Test decisivo: confrontato il salto di punteggio fra coppie di giocatori adiacenti, in una
zona affollata del pool (molti giocatori con FVM quasi identico) e in una zona rada (top
player, differenze reali grandi).

```
Zona affollata (32 giocatori tutti a FVM=12):
  Luperto FVM=12 -> Gandelman FVM=13   (gap reale: 1 punto)
  salto min-max (attuale): 0.0141      salto rank-esponenziale: 0.1519

Zona rada (top player):
  Pulisic FVM=100 -> Svilar FVM=105    (gap reale: 5 punti, 5x piu' grande)
  salto min-max (attuale): 0.0089      salto rank-esponenziale: 0.1535
```

Il metodo rank-esponenziale dà **lo stesso salto di punteggio** a Gandelman (1 punto di
differenza reale, ma è uscito da un affollamento di 32 giocatori identici) e a Svilar (5
punti di differenza reale, un gap 5 volte più grande). Il rank premia "quanti giocatori hai
superato in classifica", non "quanto sei davvero più forte" — la sua "garanzia" di scalini
2-3x consistenti è una separazione **artificiale**, imposta dalla densità del pool in quella
zona, non dai veri divari di qualità. È esattamente il rischio di "troppa separazione" da
evitare.

**Verdetto: il metodo rank-esponenziale è scartato.** Nonostante risolvesse elegantemente il
vincolo "scalini 2-3x ovunque", lo fa al prezzo di ignorare il valore reale sottostante — un
compromesso peggiore, non migliore, del metodo attuale.

**Si resta sul metodo min-max + compressione logaritmica** (`normalizeScore.m`, invariato),
con `αF=2`, `αQ=0.08`, `φ=0.40` — già applicati. Rispetta la magnitudine reale dei dati (non
solo l'ordine), è misurabilmente più stabile del rank-esponenziale, e soddisfa già il
vincolo principale (top/mediano = 2.34, dentro banda 2-3x) senza introdurre distorsioni
artificiali legate alla densità locale del pool.

## 7. Raccomandazione finale

**Metodo**: min-max + compressione logaritmica (`normalizeScore.m`), invariato — il metodo
alternativo rank-esponenziale (§6c/6d) è stato progettato, testato e scartato dopo verifica.

| Parametro | Valore precedente | Valore raccomandato | Perché |
|---|---|---|---|
| `alphaF` | 0.03 | **2** | rapporto score(top)/score(mediano) = 2.34, dentro la banda 2-3x voluta |
| `alphaQ` | 0.0005 | **0.08** | stesso vincolo 2-3x (rapporto 2.38), scala diversa perché QUOT ha raggio piu' piccolo |
| `pLow` | 0 | **0** (invariato) | tagliare percentili appiattisce i top player, peggio che comprimere |
| `pHigh` | 1 | **1** (invariato) | idem |
| `phi` | 0.5 | **0.40** (QUOT 60%) | FVM volatile ma utile a differenziare, QUOT stabile va pesato di più |

## Nota metodologica

Prima versione di questa analisi cercava la minima asimmetria statistica (skewness vicina a
zero) — **scartata** perché non è il vincolo giusto: una distribuzione perfettamente
simmetrica cancellerebbe il vantaggio reale dei giocatori più forti. Il vincolo corretto,
chiarito dal proprietario della lega, è economico/di gioco: quanti giocatori di fascia
inferiore servono per eguagliare il valore di uno di fascia superiore. La risposta voluta è
"2-3", misurata direttamente sul rapporto fra i punteggi normalizzati, non sull'asimmetria
della curva.

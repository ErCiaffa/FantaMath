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

## 7. Raccomandazione finale

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

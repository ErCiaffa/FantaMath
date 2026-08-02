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

## 3. Risultato FVM

```
alphaF     skew
0.00001    3.65   <- quasi nessuna compressione, quasi tutti bassi
0.03       1.80
1.0        0.52
10         0.20
100        0.15   <- pavimento: oltre non cambia più (limite log puro)
1000+      0.145  (piatto)
```

L'asimmetria scende sempre, mai sotto zero, e **si appiattisce (converge) intorno a 0.145
per αF ≥ 100** — quel valore è il limite matematico di `log(1+alpha*x)` quando `alpha` è
enorme: diventa equivalente a normalizzare direttamente `log(FVM)`, l'effetto di `alpha`
stesso scompare.

**Scelta: αF = 8.** Non il valore che minimizza di più l'asimmetria (100+), ma il punto in
cui i miglioramenti diventano marginali — da 8 a 100 l'asimmetria scende solo da ~0.25 a
0.15, un guadagno piccolo a fronte di una compressione molto più aggressiva. A αF=8 i
top-player restano nettamente sopra la media (giusto, un fenomeno deve valere di più), ma
la massa di giocatori medio-bassi non è più tutta schiacciata vicino a zero.

## 4. Risultato QUOT

```
alphaQ    skew
0.0001    0.77
0.0005    0.76   <- default precedente
0.05      0.22
0.09     ~0.00   <- attraversa lo zero
0.5      -0.66   <- oltrepassato: ora sbilanciato dall'altra parte
1.0      -0.87
```

A differenza di FVM, QUOT **attraversa lo zero** intorno a `alphaQ ≈ 0.09` e poi ridiventa
asimmetrico nella direzione opposta (troppi giocatori vicino al massimo, pochi in basso —
altrettanto sbagliato).

**Scelta: αQ = 0.08.** Qui la simmetria non è un compromesso ma il punto giusto: QUOT non
aveva una coda estrema da preservare, quindi avvicinarsi al bilanciamento reale non
sacrifica nulla di significativo (a differenza di FVM, dove spingere alla simmetria totale
avrebbe cancellato il vantaggio dei fenomeni).

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

`phi` non è una domanda statistica ma di lega: quale segnale ti fidi di più? FVM riflette
tipicamente il rendimento stagionale reale (fantamedia/voti), QUOT è spesso una quotazione
di mercato/reputazione fissata prima della stagione. Nessuna delle due analisi sopra dice
quale dei due sia "più corretto" da pesare di più — dipende da cosa vuoi che il valore di
svincolo premi: la forma attuale o la reputazione di partenza.

**Scelta: phi = 0.5 (50/50).** Senza un'indicazione esplicita su quale fonte fidarsi di più
in questa lega, il 50/50 è la scelta meno arbitraria. Punto esplicitamente aperto a
revisione quando sarà chiaro quale segnale la lega considera più affidabile.

## 7. Raccomandazione finale

| Parametro | Valore precedente | Valore raccomandato | Perché |
|---|---|---|---|
| `alphaF` | 0.03 | **8** | gomito della curva: compressione seria senza appiattire i fenomeni |
| `alphaQ` | 0.0005 | **0.08** | porta QUOT al bilanciamento reale (QUOT non aveva coda da preservare) |
| `pLow` | 0 | **0** (invariato) | tagliare percentili appiattisce i top player, peggio che comprimere |
| `pHigh` | 1 | **1** (invariato) | idem |
| `phi` | 0.5 | **0.5** (invariato, ma rivedere) | nessuna base per preferire FVM o QUOT senza sapere cosa la lega vuole premiare |

## Nota metodologica

L'obiettivo non era "il più simmetrico possibile" — una distribuzione perfettamente
simmetrica cancellerebbe il vantaggio reale dei giocatori più forti, che nel fantacalcio
DEVONO valere sproporzionatamente di più. L'obiettivo era trovare, per ciascun dato (FVM,
QUOT), il punto oltre il quale comprimere ulteriormente non porta più benefici reali —
diverso per ciascuno perché FVM e QUOT partono da forme di distribuzione molto diverse tra
loro.

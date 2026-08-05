# Modello di valutazione — formule e logica

Questo documento descrive in modo formale la pipeline di calcolo che FantaManager usa per
trasformare i dati ufficiali di un giocatore (FVM, quotazione, ruolo, età) in un valore
economico utilizzabile in asta e in un prezzo di svincolo netto. È la referenza tecnica per
chi deve capire *come* nasce ogni numero mostrato in UI, non un log delle decisioni prese
durante lo sviluppo (per quello vedi `decisioni-e-logica.md`).

Tutti i parametri citati sono modificabili dal proprietario della lega dalle pagine
Formula valori / Ruoli / Età / Tasse / Lista giocatori. I valori riportati qui come esempio
sono quelli in uso al momento della stesura di questo documento — non sono costanti fisse
del motore.

## Indice

1. [Panoramica della pipeline](#1-panoramica-della-pipeline)
2. [Normalizzazione FVM/QUOT](#2-normalizzazione-fvmquot)
3. [Scarsità di ruolo](#3-scarsità-di-ruolo)
4. [Modificatore di ruolo manuale](#4-modificatore-di-ruolo-manuale)
5. [Duttilità multi-ruolo](#5-duttilità-multi-ruolo)
6. [Peso età](#6-peso-età)
7. [Valore assemblato (assembleWeight)](#7-valore-assemblato-assembleweight)
8. [Conversione in crediti d'asta](#8-conversione-in-crediti-dasta)
9. [Tassazione di svincolo](#9-tassazione-di-svincolo)
10. [Invariante di budget](#10-invariante-di-budget)
11. [Valore squadra e totale lega](#11-valore-squadra-e-totale-lega)
12. [Riferimento parametri](#12-riferimento-parametri)

---

## 1. Panoramica della pipeline

```
FVM, QUOT  ──▶  normalizzazione  ──▶  mix (S)  ──┐
                                                   ├──▶  assembleWeight  ──▶  crediti d'asta  ──▶  netto svincolo
ruolo, età ──▶  modificatore + duttilità + età ──┘
```

Ogni stadio produce un numero indipendente, sommato (non moltiplicato) nello stadio
successivo: un giocatore forte in un ruolo scarso non "esplode" per effetto moltiplicativo
di più bonus contemporanei — è una scelta di design esplicita (§7).

## 2. Normalizzazione FVM/QUOT

Implementato in `+src/+engine/normalizeScore.m` e `mixScores.m`.

```
rawLog = log(1 + alpha · raw)
lo     = percentile(rawLog, pLow · 100)
hi     = percentile(rawLog, pHigh · 100)
score  = clip((rawLog − lo) / (hi − lo), 0, 1)

S = phi · F_score + (1 − phi) · Q_score
```

- `F_score`/`Q_score`: FVM e quotazione, normalizzati indipendentemente con lo stesso
  procedimento (compressione logaritmica + min-max sul pool intero dei giocatori).
- `alpha` comprime la coda dei valori alti prima della normalizzazione — controlla quanto
  un top player si distacca dalla media, non solo la scala.
- `pLow`/`pHigh` tagliano gli estremi (winsorizing) prima del min-max. Tenuti a 0/1 (nessun
  taglio): tagliare i percentili appiattisce più top player allo stesso punteggio massimo,
  effetto indesiderato verificato sui dati reali.
- `phi` pesa il mix tra i due segnali: `phi=1` → solo FVM, `phi=0` → solo quotazione.

**Criterio di calibrazione di `alpha`**: non simmetria statistica, ma un vincolo di gioco —
"quanti giocatori di fascia media servono per eguagliare un top player" (2-3, per questa
lega). `alphaF` e `alphaQ` non sono confrontabili tra loro: FVM e QUOT hanno scale diverse
(range ~1-350 contro ~1-33).

Dettaglio analitico completo, inclusi i metodi alternativi testati e scartati, in
`normalizzazione-fvm-quot.md`.

## 3. Scarsità di ruolo

Implementato in `+src/+engine/roleDemand.m` e `roleScarcity.m`. **Solo informativo**: non
entra mai automaticamente nel valore finale del giocatore — alimenta la colonna
"Consigliato" nella pagina Ruoli, come riferimento per chi imposta il modificatore manuale
(§4).

```
D_r  = domanda del ruolo r, media sui moduli tattici Mantra standard, scalata per numero
       di squadre in lega
Q_r  = Σ (1 + qw · S(g))  per ogni giocatore g non-fuori-lista che copre il ruolo r
S_r  = mixOwned · Q_r(solo posseduti) + (1 − mixOwned) · Q_r(tutti)
Scar_r      = (D_r / max(1, S_r)) ^ eta
ScarNorm_r  = Scar_r / mediana(Scar su ruoli con domanda o offerta non nulla)
```

I giocatori "fuori lista" sono esclusi da ogni aggregato di questa formula.

Il "Consigliato" mostrato in UI usa invece una metrica più diretta, pensata per rispondere
alla domanda reale di uno svincolo — "se perdo questo giocatore, quanto sono peggiori le
alternative libere rimaste?":

```
gapPct_r    = (FVM medio posseduti_r − FVM medio liberi_r) / FVM medio posseduti_r × 100
recommended_r = min-max di gapPct su tutti i 12 ruoli, mappato su [1.00, 1.20]
```

Un ruolo dove i liberi rimasti sono molto più deboli dei posseduti (es. portieri) ottiene un
"Consigliato" più alto: è più costoso da rimpiazzare.

## 4. Modificatore di ruolo manuale

Ogni ruolo Mantra ha un moltiplicatore `roleOverride` (default 1.0, nessun effetto),
impostato a mano dal proprietario lega dalla pagina Ruoli — **mai calcolato o applicato
automaticamente**. Entra nella formula finale come:

```
mod(g) = MAX(roleOverride_r − 1)  su ogni ruolo r che il giocatore g copre
```

(`roleMod.m`). Un giocatore multi-ruolo prende il modificatore più favorevole tra quelli
posseduti, non la somma.

## 5. Duttilità multi-ruolo

Bonus additivo per chi copre più ruoli Mantra, a step (non lineare):

```
Flex(g) = 1.00                se g copre 1 ruolo
        = 1 + duttilita2      se g copre 2 ruoli          (default duttilita2 = 0.03)
        = 1 + duttilita3      se g copre ≥ nmax ruoli      (default duttilita3 = 0.05, nmax = 3)

duttilita(g) = Flex(g) − 1
```

## 6. Peso età

Rampa lineare, solo bonus per i giovani, mai malus per i veterani (`+src/+engine/ageWeight.m`):

```
etaWeight(g) = etaBonusMax                                              se età(g) ≤ etaFloor
             = etaBonusMax · (etaZero − età(g)) / (etaZero − etaFloor)  se etaFloor < età(g) < etaZero
             = 0                                                        se età(g) ≥ etaZero
```

Default: `etaFloor = 15` (età minima Serie A, non ha senso premiare oltre), `etaZero = 38`
(bonus esaurito), `etaBonusMax = 0.10` (+10% massimo, ai più giovani).

## 7. Valore assemblato (assembleWeight)

I quattro termini si sommano in modo puramente additivo, non moltiplicativo — con
l'additivo il tetto massimo teorico resta prevedibile (somma dei tetti singoli); con il
moltiplicativo ogni bonus amplificherebbe gli altri, rischiando di far dominare la scarsità
di ruolo sulla qualità reale del giocatore (effetto verificato e scartato con `rho=1` nella
vecchia pipeline `S × PesoRuolo`).

```
assembleWeight(g) = S(g) · (1 + mod(g) + duttilita(g) + etaWeight(g))
```

## 8. Conversione in crediti d'asta

`+src/+engine/auctionPrice.m`. Un esponente puro sul valore assemblato porterebbe il top
player alla cifra desiderata solo schiacciando decine di giocatori mediocri (non i veri
scarti) nella stessa fascia bassa di prezzo. Risolto con un offset prima della potenza:

```
shape(g) = max(0, assembleWeight(g) + offsetC) ^ expK
credito(g) = max(floor, s · shape(g))
```

dove `s` è un fattore di scala trovato per bisezione (§10) in modo che il **netto totale**
dopo tasse, non il lordo, torni esatto al budget della lega. `offsetC` ed `expK` controllano
solo la *forma* della curva (quanto si allarga la fascia bassa), non più la scala assoluta.

Default correnti: `offsetC = 0.52`, `expK = 4.5`, `floor = 1`.

## 9. Tassazione di svincolo

`+src/+engine/releaseTax.m`. Applicata al credito lordo stimato (§8) rispetto al costo
realmente pagato in asta, per ottenere l'incasso netto se il giocatore venisse svincolato
oggi:

```
plusvalenza    = max(0, valoreLordo − costo)
minusvalenza   = max(0, costo − valoreLordo)
aliquotaValore = taxEstero        se svincolo "obbligatorio" (es. cessione real
               = taxDecisionale   se svincolo "decisionale" (scelta della squadra)
tassaValore       = aliquotaValore · valoreLordo
tassaPlusvalenza  = taxPlusvalenza · plusvalenza
recuperoMinus     = taxMinusvalenza · minusvalenza
incassoNetto = max(0, valoreLordo − tassaValore − tassaPlusvalenza + recuperoMinus − taxFee)
```

Default correnti: `taxEstero = 0`, `taxDecisionale = 0.15`, `taxPlusvalenza = 0.10`,
`taxMinusvalenza = 0.15` (recupero su minusvalenza), `taxFee = 0`. L'app mostra sempre il
netto assumendo motivo "decisionale" (il più comune), come anteprima.

## 10. Invariante di budget

Vincolo esplicito e verificato (non un'approssimazione): **se tutti i giocatori posseduti
venissero svincolati oggi, contemporaneamente, per motivo decisionale, la somma dei netti
deve tornare esatta al pool di lega ancora "in gioco" nei giocatori**:

```
budget = Σ creditiIniziali · (1 + epsilon) − Σ residuo(squadra)
```

`residuo(squadra)` = banca attuale + bonus/malus (§11), sempre sottratto dal pool teorico
(2026-08-05). Motivo: `residuo` è contante già fermo fuori da qualsiasi giocatore — se non
lo sottraessimo, un bonus dato a una squadra gonfierebbe il pool usato per scalare il valore
di **tutti** i giocatori di lega, senza mai ridurlo (doppio conteggio: la stessa ricchezza
contata sia come banca sia come valore-giocatori). Nota: la banca è tracciata a mano
(`bankOverride`), non derivata automaticamente da `creditiIniziali − costi pagati` — se la
banca inserita a mano diverge dalla spesa reale, l'invariante diverge di conseguenza.

Il fattore di scala `s` di §8 è trovato per bisezione: `netSumFor(s) = Σ IncassoNetto(s ·
shape(g))` è monotona crescente in `s`, quindi un'unica bisezione converge in poche decine
di iterazioni a `netSumFor(s) = budget`. Di conseguenza il valore lordo (`creditoStimato`)
è una *conseguenza* del netto, non il contrario: sale automaticamente per compensare la
tassa media della lega, senza dover essere ritarato a mano ad ogni cambio di parametri
fiscali.

## 11. Valore squadra e totale lega

```
teamValue(squadra) = Σ incassoNettoDecisionale(g)   per ogni g posseduto dalla squadra
residuo(squadra)    = (bankOverride se impostato, altrimenti creditiIniziali) + Σ bonus/malus
totale(squadra)     = residuo(squadra) + teamValue(squadra)
```

`teamValue` risponde alla domanda "quanto incasserebbe la squadra se svincolasse tutta la
rosa oggi" — non il costo storico pagato in asta. Per l'intera lega, per costruzione
dell'invariante (§10):

```
Σ teamValue(squadra)  =  budget lega  (a meno di crediti mai spesi/liberi non posseduti)
```

## 12. Riferimento parametri

| Parametro | Sezione | Default corrente | Effetto |
|---|---|---|---|
| `alphaF` | §2 | 2 | Compressione coda FVM |
| `alphaQ` | §2 | 0.08 | Compressione coda QUOT |
| `phi` | §2 | 0.40 | Peso FVM nel mix (0=solo QUOT, 1=solo FVM) |
| `pLow` / `pHigh` | §2 | 0 / 1 | Percentili di taglio (nessun taglio) |
| `qw` | §3 | 1 | Peso della qualità nel conteggio scarsità |
| `eta` (scarsità) | §3 | 1 | Esponente scarsità (lineare) |
| `mixOwned` | §3 | 1 | Scarsità calcolata solo sui posseduti |
| `roleOverride` (×12 ruoli) | §4 | 1.00–1.15 (a mano) | Modificatore manuale per ruolo |
| `duttilita2` / `duttilita3` | §5 | 0.03 / 0.05 | Bonus 2 ruoli / ≥3 ruoli |
| `nmax` | §5 | 3 | Soglia ruoli per il bonus massimo |
| `etaFloor` / `etaZero` / `etaBonusMax` | §6 | 15 / 38 / 0.10 | Rampa bonus giovani |
| `offsetC` / `expK` / `floor` | §8 | 0.52 / 4.5 / 1 | Forma curva conversione in crediti |
| `taxEstero` / `taxDecisionale` | §9 | 0 / 0.15 | Aliquota su valore lordo per motivo |
| `taxPlusvalenza` / `taxMinusvalenza` | §9 | 0.10 / 0.15 | Tassa su plusvalenza / recupero su minusvalenza |
| `taxFee` | §9 | 0 | Fee fissa per svincolo |
| `epsilon` | §10 | impostato al setup lega | Margine sul budget totale |

Per la cronologia di come si è arrivati a questi valori (test, dati reali, alternative
scartate) vedi `decisioni-e-logica.md`.

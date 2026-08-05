# Come funzionano i numeri di FantaManager — guida per la lega

Questo documento spiega **senza formule** come nascono i valori che vedi in FantaManager
(valore giocatore, prezzo svincolo, crediti in asta). Se hai dubbi su "perché il mio
giocatore vale X e non Y", la risposta è quasi sempre qui dentro.

Per i dettagli tecnici/matematici precisi: `FORMULE.md`. Per la storia di *perché* ogni
scelta è stata presa (incluse le alternative scartate): `decisioni-e-logica.md`.

---

## L'idea di base

Ogni giocatore parte da un **punteggio 0-1** (chiamiamolo "quanto è forte"), calcolato
incrociando due fonti ufficiali:

- **FVM** (FantaValore di Mercato) — la stima di rendimento atteso
- **Quotazione** — il prezzo di listino standard

Poi questo punteggio viene **aggiustato** con dei bonus (mai malus, tranne uno) per tenere
conto di cose che FVM/quotazione da soli non catturano bene per la nostra lega:

| Bonus | Per chi | Quanto vale (di default) |
|---|---|---|
| **Modificatore ruolo** | Ogni ruolo Mantra ha il suo, deciso a mano dal proprietario lega | Da 0% a +15% a seconda del ruolo |
| **Duttilità** | Chi copre 2+ ruoli Mantra | +3% (2 ruoli) o +5% (3+ ruoli) |
| **Età** | Under 15-38 anni, scala linearmente | Fino a +10% per i più giovani |

Questi tre bonus **si sommano** al punteggio base (non si moltiplicano tra loro) — scelta
voluta: così il tetto massimo che un giocatore può raggiungere resta prevedibile, invece
di esplodere se capitano più bonus insieme.

**Esempio reale (Kean, oggi in lega):**

```
Punteggio base (FVM+quotazione):    0,85
+ modificatore ruolo Pc:            +0,11
+ duttilità (copre 1 solo ruolo):   +0,00
+ bonus età:                        +0,06
────────────────────────────────────────
Valore finale:                      0,99   (su una scala 0-1, quasi il massimo)
```

---

## Dal valore ai crediti

Il valore 0-1 da solo non dice quanti crediti vale un giocatore in asta — serve convertirlo
in una scala di crediti reale, calibrata sul budget della vostra lega specifica (non un
numero fisso uguale per tutte le leghe).

La conversione **schiaccia forte i valori bassi e allarga quelli alti**: due giocatori
mediocri non "fanno" un top player, un vero top player costa molto più che
proporzionalmente. Questo evita che l'app appiattisca troppi giocatori diversi sullo
stesso prezzo.

**Stesso esempio, Kean:**
```
Valore 0,99  →  92 crediti "lordi" (prezzo pieno, prima di ogni tassa)
```

---

## Tasse di svincolo — perché il "netto" è diverso dal "lordo"

Se decidi di svincolare un giocatore, non incassi il prezzo pieno ("lordo") — ci sono
delle tasse, per rendere lo svincolo una scelta reale e non gratis:

- **Tassa sul valore** (15% se scegli tu di svincolare, 0% se il giocatore è andato
  all'estero e sei "costretto") — il motivo dello svincolo conta
- **Tassa sulla plusvalenza**: se il giocatore oggi vale più di quanto l'hai pagato,
  paghi il 10% sulla differenza (come una vera plusvalenza)
- **Recupero minusvalenza**: se invece vale meno di quanto pagato, recuperi il 15% della
  perdita — un piccolo paracadute

**Kean, che hai pagato 155 e oggi vale 92 lordi (minusvalenza, l'hai pagato caro):**
```
Lordo:                    92,3
− tassa 15% sul valore:   −13,8
+ recupero minusvalenza:  +9,4  (15% della perdita rispetto ai 155 pagati)
──────────────────────────────
Netto svincolo:           87,8 crediti
```

**Muric, portiere low-cost pagato 1, oggi vale poco ma ha reso benissimo rispetto al costo (plusvalenza):**
```
Lordo:                    11,6
− tassa 15%:               −1,7
− tassa plusvalenza 10%:   −1,1  (guadagni 10,6 rispetto a quanto pagato)
──────────────────────────────
Netto svincolo:            8,8 crediti
```

L'app mostra sempre il netto **assumendo che lo svincolo sia una tua scelta** (motivo più
comune) — se un giocatore va davvero all'estero, la tassa sul valore si azzera e il netto
sale.

---

## Perché i totali di lega "tornano sempre"

Regola nascosta ma importante: **se in questo momento TUTTI i giocatori posseduti di
TUTTE le squadre venissero svincolati insieme**, la somma di tutti i netti deve tornare
esatta ai crediti totali ancora "in gioco" nella lega (crediti iniziali di tutte le
squadre, più un piccolo margine, meno quello che è già fermo in banca come contante).

Perché importa: significa che i valori non sono arbitrari o gonfiati — sono sempre
ancorati alla reale disponibilità economica della lega. Se un proprietario riceve un bonus
estra crediti, quel bonus **non** fa lievitare il valore di tutti gli altri giocatori di
lega — semplicemente sposta credito dal "pool comune" alla sua banca personale.

---

## Il modificatore di ruolo — l'unico numero deciso a mano

Tutto il resto in questa guida è calcolato automaticamente dai dati. Il **modificatore di
ruolo** invece lo decide il proprietario lega a mano, ruolo per ruolo (pagina "Ruoli"),
partendo da un riferimento — "quanto sono più deboli i liberi rimasti rispetto a chi
possiedi in quel ruolo" — ma la decisione finale resta manuale, non automatica.

Motivo: è l'unico punto dove entra un giudizio soggettivo ("questo ruolo è strategicamente
più importante nella nostra lega specifica"), tutto il resto della pipeline è meccanico e
riproducibile allo stesso modo per tutti.

---

## Domande frequenti

**"Perché il mio giocatore vale meno di quanto l'ho pagato?"**
Può succedere — il valore riflette rendimento reale + ruolo + età, non quanto hai speso
all'asta. Se paghi più del "giusto" per un giocatore mediocre, il sistema non te lo
restituisce artificialmente più alto dopo. La minusvalenza ti recupera solo il 15% della
differenza, non tutto.

**"Perché due giocatori con lo stesso FVM hanno valori diversi?"**
Ruolo, età e quanti ruoli coprono cambiano il risultato finale — FVM/quotazione sono solo
il punto di partenza (il "punteggio base"), non l'ultima parola.

**"Il modificatore di ruolo è truccato per favorire qualcuno?"**
È pubblico, uguale per tutti i giocatori dello stesso ruolo (non per squadra), e visibile
nella pagina Ruoli — chiunque può controllarlo in ogni momento.

**"Se svincolo prima degli altri ho un vantaggio?"**
No — l'invariante di budget (sopra) fa sì che il valore di ogni giocatore sia già calcolato
tenendo conto di quanto la lega può realisticamente assorbire, non cambia se svincoli
prima o dopo.

---

## Tabella parametri attuali (per chi vuole i numeri esatti)

| Cosa | Valore oggi |
|---|---|
| Peso FVM vs quotazione nel punteggio base | 40% FVM / 60% quotazione |
| Bonus età massimo | +10%, per chi ha 15 anni o meno |
| Età da cui il bonus si azzera | 38 anni |
| Bonus duttilità (2 ruoli / 3+ ruoli) | +3% / +5% |
| Tassa svincolo per scelta propria | 15% sul valore |
| Tassa svincolo per cessione estero | 0% sul valore |
| Tassa plusvalenza | 10% sul guadagno |
| Recupero minusvalenza | 15% della perdita |

*(Ultimo aggiornamento: 2026-08-05. Se questi numeri cambiano, questo file va aggiornato
insieme — chiedi al proprietario lega se non coincidono con quello che vedi nell'app.)*

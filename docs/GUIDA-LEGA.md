# Come funzionano i numeri di FantaManager — guida per la lega

Questo documento spiega **senza formule** come nascono i valori che vedi in FantaManager
(valore giocatore, prezzo svincolo, crediti in asta). Se hai dubbi su "perché il mio
giocatore vale X e non Y", la risposta è quasi sempre qui dentro.

Per i dettagli tecnici/matematici precisi: `FORMULE.md`. Per la storia di *perché* ogni
scelta è stata presa (incluse le alternative scartate): `decisioni-e-logica.md`.

---

## Le due fonti ufficiali: FVM e Quotazione

Prima dei nostri calcoli, partiamo sempre da due dati **ufficiali di Fantacalcio.it**, non
inventati da noi:

**FVM (FantaValore di Mercato)** è l'indicatore ufficiale del valore teorico di un
calciatore su base 1000, aggiornato **giornalmente** dalla redazione Fantacalcio in base
alle prestazioni reali e agli eventi di mercato. Serve principalmente come riferimento per
gli svincoli (in percentuale o in totale) e per le offerte minime nelle buste di mercato.
Per adattarlo alla nostra lega, l'FVM viene **riproporzionato** sul nostro monte crediti
(FVMp) — es. un FVM di 100 su base 1000 diventa 50 se la lega ha 500 crediti totali, invece
di 1000. Dalla stagione 2025/26 è disponibile anche lo storico delle variazioni FVM nella
scheda di ogni giocatore, utile per vedere l'andamento nel tempo.

**Quotazione** è il parametro fondamentale usato dalle leghe per le compravendite nei
mercati non esclusivi (dove più giocatori condividono lo stesso ruolo). Varia durante la
stagione con un algoritmo che bilancia le prestazioni reali (fantamedia, voti, presenze)
con la quotazione iniziale (basata su storico e blasone del giocatore). Le quotazioni
ufficiali escono una volta l'anno all'evento Fantacalcio Unveil e sono pubbliche su
fantacalcio.it e sull'app Leghe Fantacalcio. In Mantra il ruolo assegnato pesa direttamente
sul valore (diversamente dal Classic, più fluido). Nella pratica, la quotazione serve a
calcolare il valore di svincolo, le operazioni di mercato, e a determinare l'FVM che
protegge i giocatori di alto profilo da cali eccessivi.

## L'idea di base

Da questi due dati ufficiali calcoliamo un **valore assoluto 0-1** per ogni giocatore — un
indicatore di **quanto quel giocatore dovrebbe rendere**, non una misura assoluta di
qualità in sé, ma una stima costruita incrociando FVM e quotazione.

Poi questo valore viene **aggiustato** con dei bonus (mai malus, tranne uno) per tenere
conto di cose che FVM/quotazione da soli non catturano bene per la nostra lega specifica:

| Bonus | Per chi | Quanto vale (di default) |
|---|---|---|
| **Modificatore ruolo** | Ogni ruolo Mantra ha il suo, calibrato sullo studio dei dati reali di lega (vedi sezione dedicata) | Da 0% a +15% a seconda del ruolo |
| **Duttilità** | Chi copre 2+ ruoli Mantra | +3% (2 ruoli) o +5% (3+ ruoli) |
| **Età** | Under 15-38 anni, scala linearmente | Fino a +10% per i più giovani |

Questi tre bonus **si sommano** al punteggio base (non si moltiplicano tra loro) — scelta
voluta: così il tetto massimo che un giocatore può raggiungere resta prevedibile, invece
di esplodere se capitano più bonus insieme.

**Esempio reale (Kean, oggi in lega):**

```
Valore assoluto (da FVM+quotazione):  0,85
+ modificatore ruolo Pc:              +0,11
+ duttilità (copre 1 solo ruolo):     +0,00
+ bonus età:                          +0,06
──────────────────────────────────────────
Valore finale:                        0,99   (su una scala 0-1, quasi il massimo)
```

---

## Dal valore ai crediti

Il valore 0-1 da solo non dice quanti crediti vale un giocatore in asta — serve convertirlo
in una scala di crediti reale, calibrata sul budget della vostra lega specifica (non un
numero fisso uguale per tutte le leghe).

La conversione riflette come funziona un'asta vera: un top player costa molto più che
proporzionalmente rispetto a un giocatore medio, perché è raro e conteso — due giocatori
mediocri insieme non valgono quanto un vero campione. La curva di conversione è tarata per
rispettare questo principio, non per "appiattire" o alterare artificialmente i prezzi.

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

## Il modificatore di ruolo — nasce da uno studio dei dati reali, non a caso

Il **modificatore di ruolo** (pagina "Ruoli") è l'unico punto della pipeline calibrato
ruolo per ruolo invece che ricavato automaticamente da FVM/quotazione — ma non è una scelta
arbitraria: parte da un'analisi diretta dei dati reali della nostra lega, calcolata così:

> per ogni ruolo, quanto sono più deboli i giocatori liberi rimasti rispetto a quelli già
> posseduti in quel ruolo (differenza media di FVM) — se perdi un giocatore in quel ruolo,
> quanto è difficile davvero rimpiazzarlo con chi c'è ancora sul mercato?

Questo numero — il "Consigliato" — è visibile e verificabile da chiunque nella pagina
Ruoli, insieme ai dati grezzi (quanti posseduti, quanti liberi, FVM medio di entrambi) che
lo generano. Il proprietario lega lo usa come riferimento diretto per calibrare il
modificatore finale: non è un numero scelto a sentimento, è il risultato di uno studio
sullo stato reale della lega, aggiornato automaticamente ogni volta che cambia il listone.

---

## Domande frequenti

**"Perché il mio giocatore vale meno di quanto l'ho pagato?"**
Può succedere — il valore riflette rendimento reale + ruolo + età, non quanto hai speso
all'asta. Se paghi più del "giusto" per un giocatore mediocre, il sistema non te lo
restituisce artificialmente più alto dopo. La minusvalenza ti recupera solo il 15% della
differenza, non tutto.

**"Perché due giocatori con lo stesso FVM hanno valori diversi?"**
Ruolo, età e quanti ruoli coprono cambiano il risultato finale — FVM/quotazione sono solo
il punto di partenza (il "valore assoluto"), non l'ultima parola.

**"Il modificatore di ruolo è truccato per favorire qualcuno?"**
No — nasce dallo studio dei dati reali di lega (vedi sopra), è uguale per tutti i giocatori
dello stesso ruolo (non per squadra o per manager), e sia il numero che i dati grezzi che
lo generano sono pubblici nella pagina Ruoli — chiunque può controllarli in ogni momento.

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

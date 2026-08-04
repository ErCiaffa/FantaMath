# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Due profili: il proprietario della lega (te), che calcola/tara i parametri della formula di valutazione (ruoli, età, duttilità, tasse, conversione in crediti) e gestisce squadre/rose/banca; i membri della lega, che consultano prezzi di svincolo, liste giocatori e valori squadra — non modificano parametri.

## Product Purpose

Motore di valutazione economica per una lega fantacalcio manageriale pluriennale: calcola il valore di svincolo/asta di ogni giocatore da FVM/QUOT + scarsità ruolo + età + tassazione, gestisce budget/rose/transazioni delle squadre nel tempo, esporta liste prezzi utilizzabili durante asta/svincoli reali. Successo = una lista prezzi che la lega considera corretta e su cui può basare decisioni economiche reali (crediti veri, non un gioco a parte).

## Positioning

A differenza di un semplice listone/quotazioni ufficiali, combina scarsità di ruolo reale (calcolata sui dati della lega, non generica), un modello economico multi-stagione (plusvalenza/minusvalenza, tassazione differenziata per motivo di svincolo) e un invariante di budget verificabile (il netto dopo tasse torna sempre esatto al totale crediti lega) — parametri tutti tarabili dal proprietario, non fissi.

## Operating Context

Backend MATLAB (motore di calcolo, poller su coda file) + FastAPI (bridge) + frontend HTML/JS servito staticamente. Il proprietario carica un CSV listone periodicamente, tara i parametri da pagine dedicate (Ruoli, Età, Tasse, Formula valori, conversione crediti), i membri lega guardano Dashboard/Lista giocatori. Nessuna pipeline automatica di dati esterni.

## Capabilities and Constraints

- Multi-lega (switch tra leghe dalla UI).
- Formula di valore componibile e tarabile: normalizzazione FVM/QUOT → mix φ → scarsità ruolo (informativa) → modificatore ruolo manuale + duttilità multi-ruolo + bonus età (tutti additivi) → conversione in crediti (curva a potenza con offset, calibrata sul budget) → tassazione svincolo (motivo estero/decisionale + plusvalenza/minusvalenza).
- Vincolo esplicito: se tutti i giocatori posseduti venissero svincolati contemporaneamente, il totale NETTO (dopo tasse) deve tornare esatto al budget lega (crediti iniziali × (1+epsilon)) — invariante verificato via bisezione, non un'approssimazione.
- Dato mancante/bloccante (ruolo non riconosciuto, costo mancante per un posseduto) → errore esplicito, mai fallback silenzioso.
- Nessun requisito di accessibilità formale raccolto: utenza è la lega privata (poche persone), non pubblico generale.

## Brand Commitments

Nessuno — nessun nome/logo/palette esistente da preservare, libertà totale sull'identità visiva (confermato dal proprietario).

## Evidence on Hand

Nessun asset di marca. Dati reali disponibili per test/anteprima: listone corrente (664 giocatori, 313 posseduti, 10 squadre) e un export storico di un'altra lega/stagione (prezzi di svincolo accettati) usato per validare le formule — riferimento numerico, non materiale di marca.

## Product Principles

1. Ogni parametro della formula è visibile e modificabile dal proprietario, mai un numero nascosto nel codice — la UI deve sempre mostrare da dove viene un valore, non solo il risultato.
2. Mai un fallback silenzioso su dati incompleti o formule ambigue: se manca un input, l'interfaccia deve dirlo chiaramente, non stimare a caso.
3. La UI serve prima chi tara i parametri (bisogno di capire l'effetto di un cambiamento, quindi dati/grafici accanto agli input) e poi chi consulta i risultati (bisogno di leggere in fretta prezzi/valori chiari).
4. Correttezza numerica prima dell'estetica: qualunque scelta grafica non deve mai oscurare o confondere un numero che rappresenta crediti reali.

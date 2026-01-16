# FantaMath

Mathlab version R2024a
Download csv in https://leghe.fantacalcio.it/{lega}/market/players
========================================
FantaEconomy — Formule complete (Mantra)
Versione: Log-Control + Ruoli + Pool fisso + W* dinamico perfetto
========================================

OBIETTIVO
---------
Definire un valore equo per ogni calciatore che:
1) rispecchi forza/percezione (FVM + Quotazione)
2) tenga conto della rarità dei ruoli Mantra e della duttilità
3) mantenga la moneta stabile: il valore totale “nuovo” distribuito ai giocatori NON crea inflazione
4) gestisca cashout svincoli con regole diverse (obbligatorio vs decisionale)

IDEA CHIAVE (anti-inflazione reale)
-----------------------------------
In lega esistono già crediti liquidi nelle banche delle squadre.
Se tu calcoli i nuovi valori dei giocatori ignorando questo, crei inflazione implicita.

Quindi:
- la lega ha una “ricchezza target” totale (MoneyTarget)
- una parte è già LIQUIDA nelle banche (Liquidità attuale)
- il resto deve stare nei GIOCATORI (pool valori giocatori W*)

Perciò:
W* = MoneyTarget − LiquiditàAttualeNetta

------------------------------------------------------------
0) NOTAZIONE DATI (per ogni giocatore i)
------------------------------------------------------------
F_i   = FVM (es. 260)
Q_i   = QUOT attuale (es. 30)
C_i   = costo pagato dalla squadra (prezzo d’acquisto)
R_i   = insieme ruoli Mantra del giocatore (es. {W,A}, {DC,B}, {T/A/PC})
n_i   = |R_i| numero ruoli ricopribili (duttilità)
g_i   = 1 se svincolo obbligatorio (estero/fuori lista), 0 altrimenti
own_i = 1 se posseduto in lega (owned==1), 0 se libero

IMPORTANTE:
- Tutto il modello valuta SOLO i giocatori owned==1 (la ricchezza deve stare in rosa)
- I giocatori liberi non rappresentano ricchezza reale per una squadra

Set ruoli:
P  = Portiere
Dd = Terzino destro
Ds = Terzino sinistro
Dc = Difensore centrale
B  = Braccetto
E  = Esterno
M  = Mediano
C  = Centrocampista
T  = Trequartista
W  = Ala
A  = Attaccante
Pc = Punta centrale

Classi di stampo (vincolo moduli):
Difensivi:  D = {Dd, Ds, Dc, B, E, M}
Offensivi:  O = {C, T, W, A, Pc}
Portiere:   {P}

------------------------------------------------------------
1) PARAMETRI MODIFICABILI (tutti)
------------------------------------------------------------

(1) Peso FVM vs QUOT
φ ∈ [0,1]  = peso del FVM nella forza del giocatore
            (1-φ) è il peso della QUOT

(2) Log-Control per FVM (senza percentili)
α_F > 0    = intensità compressione log sul FVM
F_ref > 0  = riferimento massimo/stabile del FVM (scala). Es: 350–400

(3) Log-Control per QUOT (consigliato)
α_Q > 0    = intensità compressione log sulla QUOT
Q_ref > 0  = riferimento massimo QUOT (scala). Es: 35–40

(4) Separazione TOP vs medi
γ ≥ 1      = esponente: S_pow = S^γ (γ>1 separa top)

(5) Floor matematico anti-1 (nessuna IF)
μ ≥ 0      = forza del minimo tecnico sopra 1
k > 0      = soglia di attivazione (più alto = floor più lento)
p ≥ 1      = curva floor (1 lineare, 2 più selettivo)

(6) Ruoli: rarità e impatto sul prezzo
η ≥ 0      = aggressività scarsità ruolo: (Domanda/Offerta)^η
ρ ≥ 0      = peso della rarità ruolo nel prezzo del giocatore

(7) Duttilità (numero ruoli)
β ≥ 0      = bonus max multi-ruolo (tipico 0.05–0.20)
n_max      = massimo # ruoli nel dataset (tipico 3 o 4)

(8) Economia globale (banca centrale)
T          = numero squadre
C_start    = crediti iniziali per squadra (es. 500)
ε ≥ 0      = margine di crescita consentita sul target (es. 0.10–0.20)
Cb         = bonus globali creati dalla lega (premi)
Cp         = penalità globali rimosse dalla lega (malus; negativo o 0)
Cash_now   = liquidità attuale nelle banche (somma crediti squadre)

(9) Svincoli / CashOut
t_plus ≥ 0 = tassa sulla plusvalenza
t_gE ≥ 0   = tassa sul valore totale V per svincolo obbligatorio
t_gV ≥ 0   = tassa sul valore totale V per svincolo decisionale
f ≥ 0      = fee fissa per svincolo

------------------------------------------------------------
2) FVM e QUOT SENZA NORMALIZZAZIONI A PERCENTILI
   (solo log controllabile + scale fisse)
------------------------------------------------------------

2.1) FVM compressa e scalata
F_comp(i)  = ln(1 + α_F * F_i)
F_scale    = ln(1 + α_F * F_ref)
F_score(i) = min(1, F_comp(i) / F_scale)

2.2) QUOT compressa e scalata
Q_comp(i)  = ln(1 + α_Q * Q_i)
Q_scale    = ln(1 + α_Q * Q_ref)
Q_score(i) = min(1, Q_comp(i) / Q_scale)

2.3) Score base forza
S(i)     = φ * F_score(i) + (1-φ) * Q_score(i)
S_pow(i) = S(i)^γ

Interpretazione rapida:
- α_F ↑ comprime di più i top FVM
- α_Q ↑ comprime QUOT (utile se QUOT satura e “appiattisce”)
- γ ↑ fa esplodere differenze top (se vuoi top quasi doppi)

------------------------------------------------------------
3) FLOOR ANTI-1 (minimo tecnico matematico)
------------------------------------------------------------

Qualità minima:
d(i) = F_score(i) + Q_score(i)  (range 0..2)

Floor:
Floor(i) = 1 + μ * ( d(i)^p / ( d(i)^p + k ) )

Effetto:
- veri scarsi -> Floor ~ 1
- giocatori decenti -> Floor > 1
- limite -> 1+μ

------------------------------------------------------------
4) RUOLI MANTRA: OFFERTA, DOMANDA, SCARSITÀ
------------------------------------------------------------

4.1) OFFERTA per ruolo r (calcolabile dai tuoi giocatori)
S_r = Σ_{i: own_i=1} 1( r ∈ R_i )

Interpretazione:
È il numero di giocatori posseduti che possono coprire il ruolo r.
Questa è la “disponibilità reale” nella tua economia.

Nota:
Puoi anche calcolare offerta totale (including free agents),
ma per economia di lega è più coerente usare owned==1.

4.2) DOMANDA per ruolo r (calcolabile dai moduli)
Hai moduli M.
Ogni modulo m ha K_m slot.
Ogni slot accetta A_{m,k} ruoli ammessi.

Peso moduli:
p_m (uniforme: 1/|M|) oppure empirico (se sai cosa usano di più).

Domanda attesa:
D_r = T * Σ_{m∈M} p_m * Σ_{k=1..K_m} [ 1(r ∈ A_{m,k}) / |A_{m,k}| ]

Spiegazione:
Uno slot "W/A" genera 0.5 domanda W e 0.5 domanda A.

4.3) SCARSITÀ ruolo
Scar_r = ( D_r / max(1, S_r) )^η

Uso max(1,S_r) per evitare divisione per 0.
Se un ruolo è quasi assente, Scar_r diventa alto (come deve essere).

4.4) NORMALIZZAZIONE scarsità
Scar_norm(r) = Scar_r / median_u( Scar_u )

Così i fattori restano centrati ~1.

4.5) FATTORE ruolo per giocatore (multi-ruolo)
Due opzioni (scegline UNA):

(A) MAX (consigliata: Mantra vero e duttilità forte)
RoleFactor(i) = max_{r ∈ R_i} Scar_norm(r)

(B) MEDIA (più morbida)
RoleFactor(i) = (1/n_i) * Σ_{r ∈ R_i} Scar_norm(r)

------------------------------------------------------------
5) DUTTILITÀ (numero ruoli) — bonus controllato
------------------------------------------------------------

n_i = |R_i|
n_max = max_i n_i

Flex(i) = 1 + β * [ ln(1 + n_i) / ln(1 + n_max) ]

------------------------------------------------------------
6) PESO COMPLETO (forza * ruolo * duttilità)
------------------------------------------------------------

Weight(i) = S_pow(i) * (RoleFactor(i))^ρ * Flex(i)

Parametri:
- ρ=0 disattiva i ruoli
- ρ=0.5 medio
- ρ=1 forte

------------------------------------------------------------
7) CALCOLO W* “PERFETTO” (anti-inflazione, escludendo liquidità già esistente)
------------------------------------------------------------

7.1) Target monetario naturale della lega
Money0 = T * C_start

7.2) MoneyTarget (con crescita controllata)
MoneyTarget = Money0 * (1 + ε)

7.3) Liquidità netta attuale (già esistente, NON va ricreata)
CashNet = Cash_now + (Cb - Cp)

Cb: bonus globali aggiunti (premi)
Cp: penalità globali (se Cp è negativo, togli ricchezza)

7.4) Pool valori giocatori (ricchezza da distribuire nei giocatori)
W* = max(0, MoneyTarget - CashNet)

Interpretazione:
- se le squadre hanno già molta liquidità, W* si abbassa automaticamente
- se sono “scariche”, W* sale (ma sempre dentro MoneyTarget)
- questo mantiene la somma (liquidità + valore giocatori) ≈ MoneyTarget

Questo è il controllo inflazione perfetto.

------------------------------------------------------------
8) PREZZO FINALE CON POOL FISSO W*
------------------------------------------------------------

Somma floor:
B = Σ_{i: own_i=1} Floor(i)

Residuo distribuibile:
R = max(0, W* - B)

Prezzo teorico:
V_raw(i) = Floor(i) + R * Weight(i) / Σ_j Weight(j)

Prezzo finale intero minimo 1:
V(i) = max(1, round(V_raw(i)))

GARANZIA:
Σ_i V(i) ≈ W*    (al netto degli arrotondamenti)

------------------------------------------------------------
9) SVINCOLO / CASHOUT (tassa plus + tassa valore totale)
------------------------------------------------------------

Plusvalenza:
Π(i) = max(0, V(i) - C_i)

Tassa sul valore totale per tipo:
t_g(i) = t_gE se g_i=1 (obbligatorio)
t_g(i) = t_gV se g_i=0 (decisionale)

CashOut:
CashOut(i) = max(0, V(i) - t_g(i)*V(i) - t_plus*Π(i) - f)

Interpretazione:
- t_plus colpisce solo “soldi creati” da plusvalenze
- t_gV colpisce lo svincolo opportunistico anche senza plus
- t_gE basso per non punire chi è costretto
- f è sink fisso contro micro-svincoli

------------------------------------------------------------
10) DEFAULT CONSIGLIATI (baseline solida)
------------------------------------------------------------

FVM/QUOT:
φ     = 0.60
α_F   = 0.02
F_ref = 380
α_Q   = 0.15
Q_ref = 35
γ     = 1.45

Anti-1:
μ     = 1.2
k     = 0.55
p     = 1

Ruoli:
η     = 1.0
ρ     = 0.7

Duttilità:
β     = 0.12
n_max = 4

Economia:
T       = 10
C_start = 500
ε       = 0.15
Cb      = 0
Cp      = 0
Cash_now = somma reale banche squadre

Svincoli:
t_plus = 0.25
t_gE   = 0.02
t_gV   = 0.20
f      = 2

------------------------------------------------------------
11) PROCEDURA (in 7 passi)
------------------------------------------------------------

1) Leggi i giocatori owned==1
2) Calcola F_score(i) e Q_score(i) con log-control + ref fissi
3) Calcola Floor(i)
4) Calcola offerta ruolo S_r dai tuoi giocatori posseduti:
   S_r = Σ 1(r ∈ R_i)
5) Calcola domanda ruolo D_r dai moduli e pesi p_m
6) Calcola Scar_norm(r), poi RoleFactor(i) e Flex(i)
7) Calcola W* perfetto:
   W* = MoneyTarget - CashNet
   MoneyTarget = T*C_start*(1+ε)
   CashNet = Cash_now + (Cb - Cp)
   Poi distribuisci W* usando Weight(i) e Floor(i)
   => ottieni V(i) interi e stabili

------------------------------------------------------------
12) DEBUG GUIDA (per problemi tipici)
------------------------------------------------------------

TOP troppo basso:
- aumenta ε (MoneyTarget cresce) oppure riduci Cash_now (ma è dato)
- oppure aumenta γ (separazione) oppure aumenta φ (più FVM)

TOP troppo alto:
- riduci ε oppure aumenta α_F (più compressione FVM)

Troppi giocatori a 1–2:
- aumenta μ oppure riduci k (floor scatta prima)

Kean vs Thuram troppo distanti:
- aumenta α_F (comprime top FVM)
- riduci γ (meno separazione)
- aumenta QUOT weight (riduci φ)

Ruoli non contano:
- aumenta ρ o η

Jolly troppo premiati:
- riduci β oppure usa RoleFactor MEDIA invece di MAX

FINE FILE
========================================

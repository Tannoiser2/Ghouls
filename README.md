# Ghouls — versione digitale (Godot 4)

Versione digitale di **Ghouls**, gioco da tavolo horror per 3 o 4 giocatori di **Marco Ramadori e Stefano
Ancillai**, disegni di **Luigi Filipponi**, pubblicato da **Devil's Den** (Roma, dicembre 1992).
Un giocatore guida le orde dei Ghouls che salgono dalle fogne per conquistare la città e la Cattedrale;
gli altri organizzano la disperata difesa con volontari, folla, mine, radio e rifornimenti.
Grafica dalle scansioni della scatola originale.

**Gioca nel browser:** https://tannoiser2.github.io/Ghouls/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **3 o 4 giocatori**: il Ghoul più 2 o 3 Umani (Rosso, Verde, Giallo), ognuno persona o IA (facile,
  normale, difficile).
- **Tutte le regole del regolamento**: Covo con 11 ghoul coperti, preparazione degli Obiettivi, movimento
  dei ghoul con due dadi, esplorazione delle fogne con le tessere pescate (corridoi che devono comunicare),
  tombini con le pedine Locazione nascoste al Ghoul, segnalini numerati segreti (il più alto resta fermo,
  i numeri uguali saltano il turno), pesca delle pedine Umani, Folla, Rinforzi ghoul, Radio, Mine,
  Punti Vittoria, controllo degli Obiettivi, tiro da lontano e corpo a corpo con la trasformazione degli
  umani in ghoul in caso di parità, Sorpresa, Obiettivi devastati con i ghoul di rinforzo e i volontari
  perduti, +1 ai volontari nel proprio Obiettivo, Cimitero, Covo occupato, punteggi e «Gran Trucidatore di Ghouls».
- **Informazioni nascoste**: il Ghoul vede solo quante pedine coperte ci sono negli Obiettivi e un «?» sui
  tombini che non ha ancora attraversato; gli Umani non conoscono la forza dei ghoul finché non si
  scoprono in combattimento. Con più persone allo stesso schermo compare la schermata «Tocca a…».
- **IA** per il Ghoul (raccoglie le orde sui tombini, esplora, evita le fortezze imprendibili, tiene
  ghoul nel Cimitero) e per gli Umani (difende i propri Obiettivi e la Cattedrale, chiude le gallerie con
  le tessere, porta mine dove c'è pericolo e punti dove è al sicuro, caccia i ghoul isolati). Anche lei
  gioca lealmente, senza sbirciare le informazioni nascoste.
- **Regole complete** dal menu e in partita (REGOLE), **diario** della partita (DIARIO).

## Grafica Reborn e vista 3D
Nel menu: **Grafica** *Classica 1992* (le scansioni della scatola) o *Reborn*, e **Vista** *2D* o
*3D: città e fogne* (si cambia anche in partita con il pulsante VISTA 2D/3D).

- **Vista 3D**: le fogne sono un labirinto in rilievo. I luoghi della città aspettano in una colonna a destra;
  appena chi guarda sa dove porta un tombino, il luogo sale in «superficie», sospeso sopra quella tessera e
  collegato al tombino da un pozzo (il giocatore Ghoul li vede salire solo quando scopre i tombini).
  Con la grafica Reborn i luoghi sono diorama 3D fatti con Meshy, normali o devastati. Pedine come standee
  sulle basette; trascina col sinistro per ruotare, col destro per spostare, rotella per lo zoom.
- **Reborn**: la nuova grafica va in `assets/reborn/` con i nomi elencati in
  [`assets/reborn/LEGGIMI.md`](assets/reborn/LEGGIMI.md) (tessere, Obiettivi, pedine, copertina, Trasporto
  e, facoltative, miniature `.glb` per ghoul, volontari ed edifici). Ogni immagine che manca viene presa
  dalla grafica classica, quindi si può aggiungere un pezzo alla volta. Regole, IA e gioco online sono gli
  stessi.
- **Pareti delle fogne (Reborn, 3D)**: per ogni tessera `tools/pareti_blender.py` ricava dal disegno il contorno
  dei corridoi e in Blender alza un muro smussato che lo segue (`assets/reborn/models/tiles/*.glb`). I mattoni
  sono proiettati in coordinate del mondo (`pareti.gdshader`), quindi i corsi proseguono da una tessera
  all'altra senza giunte. Se cambi il disegno di una tessera, rilancia lo script per rifarne le pareti.

## Comandi
- Fogne: rotella per lo zoom, trascina per spostare, **Centra** per rifare l'inquadratura.
- Le locazioni in arancio sono quelle che si possono scegliere. Per muovere: clic sulla pila di partenza,
  scelta delle pedine nella barra in basso, clic sulla destinazione (il tondino del tombino per salire
  in un Obiettivo).
- Combattimento: clic su uno o più attaccanti e poi sul bersaglio; **Suggerisci** propone un'assegnazione.

## Gioco online
Dal menu, **Gioca online** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(Realtime Database, piano gratuito), con le stanze sotto `ghouls/rooms`: la sezione generica `$game` di
`firebase/database.rules.json` (già pubblicata con Titans ed El Grande) lo copre, non serve toccare le regole.

- **Chi crea la stanza** sceglie nel menu i giocatori: i posti su PERSONA diventano i posti per gli amici
  (il primo è il suo). Scrive il nome, preme *Crea una stanza* e comunica il codice di 4 lettere. Quando ci
  sono tutti preme *Inizia online*: i posti liberi li gioca l'IA.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- Ogni decisione è una mossa numerata nel database: tutti i dispositivi fanno girare lo stesso motore con
  lo stesso seme, quindi la partita è identica ovunque. Se cade la linea si rientra con lo stesso codice;
  se un giocatore tace per un minuto, al suo posto gioca l'IA finché non rientra.

## Scelte di questa versione (da verificare)
- **Alba** (regola aggiunta, nel menu: turno 20/30/40 oppure mai): se la Cattedrale resiste fino a quel
  turno vincono gli Umani. Nelle simulazioni gli Umani tendono a fare della Cattedrale una fortezza che i
  ghoul (al massimo 12 pedine mosse per turno) non riescono a prendere: senza limite la partita può non
  finire. Con l'alba al 30° turno IA contro IA vince il Ghoul circa una volta su due.
- **Tessere fogna**: le scansioni mostrano un esemplare per tipo (11 tipi più il Covo). Il mazzo è di 31
  tessere con 15 tombini (vedi `TILE_DECK` in `scripts/data/gh_data.gd`): se ricordi le quantità vere,
  basta cambiarle lì. Finite le 10 pedine Locazione, i tombini in più restano chiusi.
- Se le tessere sono finite e nessun ghoul può più raggiungere un Obiettivo intatto, vincono gli Umani.
- Il secondo «Atleti» della lista volontari è la pedina **Artisti** (– 2), come stampato sulla pedina.
- Sul retro di Radio & TV compaiono anche i Medici: vale il fronte (Fotoreporter, Giornalisti).
- Folla: 0 in combattimento. Sorpresa: pedina ghoul senza forza, scartata appena si rivela.
- I ghoul eliminati dalle mine danno il punto a chi ha portato la mina; il ghoul tolto dal Covo a inizio
  turno si sceglie per locazione (a caso fra quelli presenti).
- Più Umani nella stessa locazione combattono insieme: decide chi controlla l'Obiettivo (o chi ha più
  pedine). Ogni gruppo d'attacco ha un solo bersaglio; nel corpo a corpo chi resta senza bersaglio viene
  assegnato da solo.
- I ghoul possono scendere dagli Obiettivi devastati nelle fogne attraverso il tombino.
- Le tessere Trasporto non erano fra le scansioni: c'è il disegno del camion (`Volontari.heic`) con il
  colore del giocatore.

## Struttura
```
scripts/data/gh_data.gd      volontari, obiettivi, pedine, tessere fogna
scripts/core/engine.gd       motore delle regole (nessuna dipendenza dalla UI)
scripts/core/ai.gd           IA del Ghoul e degli Umani
scripts/net/                 Firebase (REST) e partita online in lockstep
scripts/ui/                  menu, mappa delle fogne 2D, vista 3D (board3d.gd), vista di gioco, regole
tests/sim.gd                 godot --headless --path . -s tests/sim.gd -- 30 2   (partite IA contro IA)
tests/shot.gd                xvfb-run godot --path . -s res://tests/shot.gd -- umano 10   (screenshot)
tests/online_play.gd         due dispositivi online sul finto Firebase (tests/firebase_mock.py)
assets/                      tessere, obiettivi, pedine, copertina (dalle scansioni), font OFL
```

Caratteri: Creepster (Sideshow) e Jost (Owen Earl), licenza SIL Open Font (`assets/fonts`).

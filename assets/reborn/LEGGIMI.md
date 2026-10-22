# Grafica «Reborn» di Ghouls

Metti qui le nuove immagini (PNG, JPG o WEBP) con **esattamente** questi nomi: il gioco le usa al posto delle scansioni del 1992 quando nel menu si sceglie *Grafica: Reborn*. Ogni file che manca viene sostituito dall'originale, quindi si può procedere un pezzo alla volta.

Se preferisci, mettile in `Desktop/Ludoteca/Ghouls/Reborn` con la stessa struttura di cartelle e chiedi a Claude di importarle.

## tiles/ — tessere fogna (quadrate, 1024×1024)

Disegnate nell'orientamento base: i corridoi devono uscire dai lati indicati (il gioco poi le ruota). I tombini vanno più o meno dove sono nelle tessere originali (il segnalino del tombino viene disegnato lì sopra).

| file | tessera | corridoi aperti | tombini |
|---|---|---|---|
| `covo.png` | Covo | nord, est, sud, ovest | 0 |
| `cimitero.png` | Cimitero | est, ovest | 0 |
| `t.png` | Diramazione | est, sud, ovest | 0 |
| `t2.png` | Diramazione | est, sud, ovest | 0 |
| `tt.png` | Diramazione con tombino | est, sud, ovest | 1 |
| `dritto.png` | Condotto | nord, sud | 0 |
| `dritto_t.png` | Condotto con tombino | nord, sud | 1 |
| `curva.png` | Curva | sud, ovest | 0 |
| `curva_t.png` | Curva con tombino | sud, ovest | 1 |
| `croce.png` | Incrocio | nord, est, sud, ovest | 0 |
| `croce_tt.png` | Incrocio con due tombini | nord, est, sud, ovest | 2 |
| `cieco.png` | Vicolo cieco | nord | 0 |

## objectives/ — Obiettivi (orizzontali, 1200×800)

Per ognuno il fronte e il retro devastato (`_dev`). Nome, moltiplicatore e volontari con +1 li scrive già il gioco: non servono sull'immagine (ma si possono lasciare).

- `cattedrale.png`, `cattedrale_dev.png` — Cattedrale
- `ospedale.png`, `ospedale_dev.png` — Ospedale
- `polizia.png`, `polizia_dev.png` — Polizia
- `radiotv.png`, `radiotv_dev.png` — Radio & TV
- `universita.png`, `universita_dev.png` — Università
- `residenziali.png`, `residenziali_dev.png` — Quartieri Residenziali
- `porto.png`, `porto_dev.png` — Porto
- `popolari.png`, `popolari_dev.png` — Quartieri Popolari
- `sportivo.png`, `sportivo_dev.png` — Centro Sportivo
- `commerciale.png`, `commerciale_dev.png` — Centro Commerciale

## counters/ — pedine (quadrate, 512×512)

- Ghoul: `g1.png` … `g5.png`, `sorpresa.png`, retro coperto `ghoul_back.png`
- Umani: `folla.png`, `pv1.png` `pv2.png` `pv3.png`, `mina1.png` `mina2.png` `mina3.png`, `radio.png`, `rinforzo.png`, retro coperto `human_back.png`
- Volontari (con i due valori ben leggibili, distanza a sinistra e corpo a corpo a destra):
  - `v_massaie.png` — Massaie
  - `v_studenti.png` — Studenti
  - `v_polizia.png` — Polizia
  - `v_swat.png` — Swat
  - `v_disoccupati.png` — Disoccupati
  - `v_artisti.png` — Artisti
  - `v_preti.png` — Preti
  - `v_portuali.png` — Portuali
  - `v_professori.png` — Professori
  - `v_automobilisti.png` — Automobilisti
  - `v_cacciatori.png` — Cacciatori
  - `v_verdi.png` — Verdi
  - `v_pacifisti.png` — Pacifisti
  - `v_impiegati.png` — Impiegati
  - `v_commercianti.png` — Commercianti
  - `v_yuppies.png` — Yuppies
  - `v_fotoreporter.png` — Fotoreporter
  - `v_giornalisti.png` — Giornalisti
  - `v_atleti.png` — Atleti
  - `v_ubriachi.png` — Ubriachi
  - `v_medici.png` — Medici
  - `v_degenti.png` — Degenti
  - `v_extracomunitari.png` — Extracomunitari
  - `v_punk.png` — Punk
  - `v_rpg.png` — Giocatori RPG
  - `v_drogati.png` — Drogati
  - `v_operai.png` — Operai
  - `v_pensionati.png` — Pensionati
  - `v_ultras.png` — Ultras
  - `v_motociclisti.png` — Motociclisti

## misc/
- `copertina.png` — copertina della scatola (verticale, ~1800×2400)
- `trasporto.png` — tessera Trasporto (orizzontale, ~1280×600)

## models/ — miniature 3D (facoltative, .glb)

- `ghoul.glb`, `volontario.glb`: miniature per le pile di pedine nella vista 3D (al posto degli standee).
- `cattedrale.glb`, `ospedale.glb`, … (stessi nomi degli Obiettivi): edifici della città nella vista 3D.
Vanno bene i modelli fatti con Meshy; vengono scalati in automatico.

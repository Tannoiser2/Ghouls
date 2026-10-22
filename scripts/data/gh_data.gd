class_name GHData
extends RefCounted
## Dati di Ghouls (Devil's Den, 1992), dal regolamento e dalle scansioni della scatola:
## pedine, volontari, obiettivi, tessere fogna.

## Volontari: chiave -> [nome, valore a distanza (-1 = non spara), valore corpo a corpo].
## Dalla «Lista volontari» del regolamento. Il secondo «Atleti» della lista è in realtà la pedina
## «Artisti» (- 2), come stampato sulla pedina.
const VOLUNTEERS := {
	"massaie": ["Massaie", -1, 5],
	"studenti": ["Studenti", 2, 3],
	"polizia": ["Polizia", 4, 4],
	"swat": ["Swat", 5, 5],
	"disoccupati": ["Disoccupati", -1, 4],
	"artisti": ["Artisti", -1, 2],
	"preti": ["Preti", 5, 1],
	"portuali": ["Portuali", 3, 5],
	"professori": ["Professori", -1, 1],
	"automobilisti": ["Automobilisti", -1, 4],
	"cacciatori": ["Cacciatori", 4, 2],
	"verdi": ["Verdi", -1, 2],
	"pacifisti": ["Pacifisti", 3, 1],
	"impiegati": ["Impiegati", 1, 2],
	"commercianti": ["Commercianti", 1, 3],
	"yuppies": ["Yuppies", 2, 2],
	"fotoreporter": ["Fotoreporter", 1, 3],
	"giornalisti": ["Giornalisti", -1, 2],
	"atleti": ["Atleti", -1, 2],
	"ubriachi": ["Ubriachi", 2, 1],
	"medici": ["Medici", -1, 2],
	"degenti": ["Degenti", -1, 1],
	"extracomunitari": ["Extracomunitari", -1, 3],
	"punk": ["Punk", 1, 4],
	"rpg": ["Giocatori RPG", 5, 2],
	"drogati": ["Drogati", 2, 2],
	"operai": ["Operai", 2, 4],
	"pensionati": ["Pensionati", -1, 3],
	"ultras": ["Ultras", 2, 4],
	"motociclisti": ["Motociclisti", 3, 3],
}

## Obiettivi: chiave -> nome, volontari con +1, moltiplicatore, ghouls pescati se devastato.
const OBJECTIVES := {
	"cattedrale": {"name": "Cattedrale", "vol": ["preti"], "mult": 3, "dev": 0},
	"ospedale": {"name": "Ospedale", "vol": ["medici", "degenti"], "mult": 2, "dev": 2},
	"polizia": {"name": "Polizia", "vol": ["polizia", "swat"], "mult": 2, "dev": 3},
	"radiotv": {"name": "Radio & TV", "vol": ["fotoreporter", "giornalisti"], "mult": 2, "dev": 1},
	"universita": {"name": "Università", "vol": ["professori", "studenti"], "mult": 2, "dev": 2},
	"residenziali": {"name": "Quartieri Residenziali", "vol": ["yuppies", "impiegati"], "mult": 2, "dev": 2},
	"porto": {"name": "Porto", "vol": ["portuali", "drogati"], "mult": 1, "dev": 2},
	"popolari": {"name": "Quartieri Popolari", "vol": ["pensionati", "extracomunitari"], "mult": 1, "dev": 4},
	"sportivo": {"name": "Centro Sportivo", "vol": ["atleti", "ultras"], "mult": 1, "dev": 2},
	"commerciale": {"name": "Centro Commerciale", "vol": ["commercianti", "massaie"], "mult": 1, "dev": 3},
}
const OBJ_ORDER := ["cattedrale", "ospedale", "polizia", "radiotv", "universita", "residenziali", "porto", "popolari", "sportivo", "commerciale"]

## Pedine Ghoul (nel contenitore): valore -> quantità. «S» = Sorpresa (nessuna forza).
const GHOULS := {1: 20, 2: 15, 3: 10, 4: 5, 5: 3}
const SURPRISES := 5
## Pedine Umani (nel contenitore) oltre ai 30 volontari.
const FOLLA := 18
const PV := {1: 16, 2: 10, 3: 5}
const MINES := {1: 5, 2: 4, 3: 2}
const RADIOS := 4
const REINFORCEMENTS := 9

## Tessere fogna. Lati aperti a rotazione 0: N=1, E=2, S=4, W=8. tomb = tombini sulla tessera.
## img = file dell'immagine (assets/tiles/tNN.jpg).
const TILES := {
	"covo": {"img": 2, "open": 15, "tomb": 0, "name": "Covo"},
	"cimitero": {"img": 1, "open": 10, "tomb": 0, "name": "Cimitero"},
	"t": {"img": 0, "open": 14, "tomb": 0, "name": "Diramazione"},
	"t2": {"img": 7, "open": 14, "tomb": 0, "name": "Diramazione"},
	"tt": {"img": 11, "open": 14, "tomb": 1, "name": "Diramazione con tombino", "tp": [[0.5, 0.13]]},
	"dritto": {"img": 4, "open": 5, "tomb": 0, "name": "Condotto"},
	"dritto_t": {"img": 3, "open": 5, "tomb": 1, "name": "Condotto con tombino", "tp": [[0.86, 0.42]]},
	"curva": {"img": 5, "open": 12, "tomb": 0, "name": "Curva"},
	"curva_t": {"img": 10, "open": 12, "tomb": 1, "name": "Curva con tombino", "tp": [[0.8, 0.22]]},
	"croce": {"img": 6, "open": 15, "tomb": 0, "name": "Incrocio"},
	"croce_tt": {"img": 9, "open": 15, "tomb": 2, "name": "Incrocio con due tombini", "tp": [[0.84, 0.16], [0.16, 0.84]]},
	"cieco": {"img": 8, "open": 1, "tomb": 0, "name": "Vicolo cieco"},
}
## Composizione del mazzo delle tessere fogna (il Covo si piazza al centro all'inizio).
## Dalla scatola: 20 tessere in tutto, 2 per tipo, più il Covo e il Cimitero (uno ciascuno).
## Le due Diramazioni semplici sono state scansionate entrambe (t e t2, disegni diversi).
## I tombini sono 10, quante le pedine Locazione.
const TILE_DECK := {
	"cimitero": 1, "t": 1, "t2": 1, "tt": 2, "dritto": 2, "dritto_t": 2, "curva": 2, "curva_t": 2,
	"croce": 2, "croce_tt": 2, "cieco": 2,
}

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # N E S W
const HUMAN_COLORS := ["rosso", "verde", "giallo"]
const COLOR_HEX := {"rosso": "#d8342c", "verde": "#6fae3a", "giallo": "#f2c719", "ghoul": "#7a5bd1"}
const COLOR_NAME := {"rosso": "Rosso", "verde": "Verde", "giallo": "Giallo"}


## Lati aperti di un tipo di tessera alla rotazione r (giri di 90° in senso orario).
static func open_mask(kind: String, rot: int) -> int:
	var m: int = TILES[kind]["open"]
	for i in posmod(rot, 4):
		m = ((m << 1) | (m >> 3)) & 15
	return m


static func vol_name(k: String) -> String:
	return VOLUNTEERS[k][0]


static func obj_name(k: String) -> String:
	return OBJECTIVES[k]["name"]

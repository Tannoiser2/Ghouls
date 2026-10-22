class_name GHEngine
extends Node
## Motore delle regole di Ghouls, senza dipendenze dalla UI.
## Ogni scelta passa da `decide()`: l'IA risponde subito; per le persone viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo gioca la stessa partita.
##
## Posti: 0 = giocatore Ghoul, 1..3 = giocatori Umani (Rosso, Verde, Giallo).
## Pedine (cs): id -> {t, v, k, o, loc}
##   t: "G" ghoul (v = forza 1-5), "S" sorpresa, "V" volontario (k), "F" folla, "P" punti vittoria (v),
##      "M" mina (v), "R" radio, "X" rinforzo ghoul
##   o: posto proprietario (pedine umane), -1 altrimenti
##   loc: "" = nel contenitore, "out" = fuori gioco, "c:x,y" tessera fogna, "o:chiave" obiettivo,
##        "t:posto" tessera Trasporto
##
## Tipi di richiesta (req["type"]):
##  - "pick": scelta fra options (label), risposta = indice
##  - "token": segnalino numerato segreto, options = numeri disponibili, risposta = numero
##  - "loc": scelta di una locazione in "allowed" (con "skip" si può rinunciare: ""), risposta = loc
##  - "tile": piazzamento di una tessera, options = [[x, y, rot]], risposta = indice
##  - "gmove": movimento dei ghoul, risposta = {"ids": [...], "to": loc} oppure {} per finire
##  - "hmove": movimento dei volontari, risposta = {"ids": [...], "to": loc} oppure {} per finire
##  - "objs": scelta di "count" obiettivi in "allowed", risposta = array di chiavi
##  - "dist": distribuzione delle pedine "ids" sugli obiettivi "objs", risposta = {id: chiave}
##  - "attacks": assegnazione degli attacchi (mode = ranged / hmelee / gmelee), risposta =
##    array di [ [attaccanti], [bersagli] ]

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)

const D = preload("res://scripts/data/gh_data.gd")
const START_GHOULS := 11
const COVO_TURNS := 5

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false

# ---- configurazione
var players: Array = []          # {name, ai, level, role, color}
var nh := 2                      # giocatori umani
var max_turns := 40

# ---- materiali
var cs: Dictionary = {}
var gpool: Array = []
var hpool: Array = []
var tiles: Dictionary = {}       # "x,y" -> {k, r, tomb: [chiave obiettivo o ""]}
var tile_deck: Array = []
var loc_tokens: Array = []
var ghoul_known: Dictionary = {} # obiettivi di cui il Ghoul conosce il tombino
var objs: Dictionary = {}        # chiave -> {owner, dev}
var tokens_used: Array = []      # per posto: numeri già giocati
var played: Dictionary = {}      # numeri giocati in questo turno (posto -> numero)
var kills: Array = []            # punti per ghoul eliminati, per posto

# ---- svolgimento
var turn_no := 0
var phase := ""
var current := -1
var active_human := -1
var dice: Array = []             # ultimo lancio (per la UI)
var gmove_left := 0
var moved: Dictionary = {}       # pedine già mosse in questa fase
var main_move_used := false
var radio_used: Dictionary = {}
var gatk: Dictionary = {}        # locazioni in cui hanno attaccato i ghoul (sorpresa)
var hatk: Dictionary = {}
var covo_streak := 0
var combat: Dictionary = {}      # combattimento in corso (per la UI)
var revealed: Dictionary = {}    # ghoul scoperti nel combattimento in corso
var game_over := false
var winner := ""                 # "ghoul" / "umani"
var end_reason := ""
var results: Array = []
var log_lines: Array = []
var _next_id := 0


# ================================================================ preparazione

func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	ai_delay = float(config.get("ai_delay", 0.0))
	max_turns = int(config.get("max_turns", 40))
	players = []
	var seats: Array = config["seats"]
	nh = seats.size() - 1
	for i in seats.size():
		var s: Dictionary = seats[i]
		var col: String = "ghoul" if i == 0 else D.HUMAN_COLORS[i - 1]
		players.append({"name": str(s.get("name", "")), "ai": bool(s.get("ai", false)), "level": int(s.get("level", 1)),
			"role": "ghoul" if i == 0 else "human", "color": col})
	tokens_used = []
	kills = []
	for i in players.size():
		tokens_used.append([])
		kills.append(0)
	_build()


func _new_counter(t: String, v := 0, k := "") -> int:
	var id := _next_id
	_next_id += 1
	cs[id] = {"t": t, "v": v, "k": k, "o": -1, "loc": ""}
	return id


func _build() -> void:
	cs = {}
	gpool = []
	hpool = []
	for v in D.GHOULS:
		for i in D.GHOULS[v]:
			gpool.append(_new_counter("G", v))
	for i in D.SURPRISES:
		gpool.append(_new_counter("S"))
	for k in D.VOLUNTEERS:
		hpool.append(_new_counter("V", 0, k))
	for i in D.FOLLA:
		hpool.append(_new_counter("F"))
	for v in D.PV:
		for i in D.PV[v]:
			hpool.append(_new_counter("P", v))
	for v in D.MINES:
		for i in D.MINES[v]:
			hpool.append(_new_counter("M", v))
	for i in D.RADIOS:
		hpool.append(_new_counter("R"))
	for i in D.REINFORCEMENTS:
		hpool.append(_new_counter("X"))
	_shuffle(gpool)
	_shuffle(hpool)
	tile_deck = []
	for k in D.TILE_DECK:
		for i in D.TILE_DECK[k]:
			tile_deck.append(k)
	_shuffle(tile_deck)
	loc_tokens = D.OBJ_ORDER.duplicate()
	_shuffle(loc_tokens)
	objs = {}
	for k in D.OBJ_ORDER:
		objs[k] = {"owner": -1, "dev": false}
	tiles = {"0,0": {"k": "covo", "r": 0, "tomb": []}}


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _fx(kind: String, data: Dictionary) -> void:
	if not headless:
		fx.emit(kind, data)


func log_msg(t: String) -> void:
	log_lines.append(t)
	log_added.emit(t)


func pname(s: int) -> String:
	if s < 0 or s >= players.size():
		return "?"
	var p: Dictionary = players[s]
	if s == 0:
		return p["name"] if p["name"] != "" else "Ghoul"
	var c: String = D.COLOR_NAME[p["color"]]
	return c if p["name"] == "" or p["name"] == c else "%s (%s)" % [p["name"], c]


func d6() -> int:
	return rng.randi_range(1, 6)


# ================================================================ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	changed.emit()
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


func pick(seat: int, ctx: String, title: String, options: Array, extra := {}) -> int:
	if options.is_empty():
		return -1
	var req := {"type": "pick", "ctx": ctx, "title": title, "options": options}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	return clampi(int(c) if (c is int or c is float) else 0, 0, options.size() - 1)


func choose_loc(seat: int, ctx: String, title: String, allowed: Array, skip := false, extra := {}) -> String:
	if allowed.is_empty():
		return ""
	if allowed.size() == 1 and not skip:
		return allowed[0]
	var req := {"type": "loc", "ctx": ctx, "title": title, "allowed": allowed, "skip": skip}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	var s := str(c) if c != null else ""
	if s in allowed:
		return s
	return "" if skip else allowed[0]


# ================================================================ interrogazioni

func ids_at(loc: String, types := "") -> Array:
	var out := []
	for id in cs:
		var c: Dictionary = cs[id]
		if c["loc"] == loc and (types == "" or types.contains(c["t"])):
			out.append(id)
	out.sort()
	return out


func ghouls_at(loc: String) -> Array:
	return ids_at(loc, "GS")


func humans_at(loc: String) -> Array:
	return ids_at(loc, "VF")


func is_ghoul(id: int) -> bool:
	return cs[id]["t"] == "G" or cs[id]["t"] == "S"


func gval(id: int) -> int:
	return int(cs[id]["v"]) if cs[id]["t"] == "G" else 0


func hranged(id: int) -> int:
	var c: Dictionary = cs[id]
	if c["t"] != "V":
		return -1
	var r: int = D.VOLUNTEERS[c["k"]][1]
	if r < 0:
		return -1
	return r + bonus(id)


func hmelee(id: int) -> int:
	var c: Dictionary = cs[id]
	if c["t"] != "V":
		return 0
	return int(D.VOLUNTEERS[c["k"]][2]) + bonus(id)


## +1 ai volontari che combattono nell'obiettivo che porta il loro nome.
func bonus(id: int) -> int:
	var c: Dictionary = cs[id]
	var loc: String = c["loc"]
	if c["t"] != "V" or not loc.begins_with("o:"):
		return 0
	var ok := loc.substr(2)
	return 1 if c["k"] in D.OBJECTIVES[ok]["vol"] else 0


func cname(id: int) -> String:
	var c: Dictionary = cs[id]
	match c["t"]:
		"G":
			return "Ghoul %d" % c["v"]
		"S":
			return "Sorpresa"
		"V":
			return D.vol_name(c["k"])
		"F":
			return "Folla"
		"P":
			return "Punti Vittoria %d" % c["v"]
		"M":
			return "Mina %d" % c["v"]
		"R":
			return "Radio"
		"X":
			return "Rinforzo ghoul"
	return "?"


func loc_name(loc: String) -> String:
	if loc.begins_with("o:"):
		return D.obj_name(loc.substr(2))
	if loc.begins_with("t:"):
		return "Trasporto %s" % D.COLOR_NAME[players[int(loc.substr(2))]["color"]]
	if loc.begins_with("c:"):
		var t: Dictionary = tiles.get(loc.substr(2), {})
		if t.is_empty():
			return "fogna"
		var nm: String = D.TILES[t["k"]]["name"]
		return nm if t["k"] in ["covo", "cimitero"] else "fogna (%s)" % loc.substr(2)
	return loc


static func cell(loc: String) -> Vector2i:
	var p := loc.substr(2).split(",")
	return Vector2i(int(p[0]), int(p[1]))


static func cloc(v: Vector2i) -> String:
	return "c:%d,%d" % [v.x, v.y]


func tile_mask(key: String) -> int:
	var t: Dictionary = tiles[key]
	return D.open_mask(t["k"], t["r"])


func covo_loc() -> String:
	return "c:0,0"


func cimitero_loc() -> String:
	for key in tiles:
		if tiles[key]["k"] == "cimitero":
			return "c:" + key
	return ""


## Tessere raggiungibili da una tessera attraverso i corridoi (entrambi i lati aperti).
func tile_neighbors(loc: String) -> Array:
	var out := []
	var p := cell(loc)
	var key := "%d,%d" % [p.x, p.y]
	if not tiles.has(key):
		return out
	var m := tile_mask(key)
	for d in 4:
		if m & (1 << d) == 0:
			continue
		var q: Vector2i = p + D.DIRS[d]
		var qk := "%d,%d" % [q.x, q.y]
		if tiles.has(qk) and tile_mask(qk) & (1 << ((d + 2) % 4)) != 0:
			out.append(cloc(q))
	return out


## Lati aperti di una tessera che danno su caselle vuote (da esplorare).
func frontier_of(loc: String) -> Array:
	var out := []
	var p := cell(loc)
	var key := "%d,%d" % [p.x, p.y]
	var m := tile_mask(key)
	for d in 4:
		if m & (1 << d) == 0:
			continue
		var q: Vector2i = p + D.DIRS[d]
		if not tiles.has("%d,%d" % [q.x, q.y]):
			out.append(cloc(q))
	return out


func tombs_of(loc: String) -> Array:
	var key := loc.substr(2)
	if not tiles.has(key):
		return []
	var out := []
	for t in tiles[key]["tomb"]:
		if t != "":
			out.append(t)
	return out


## Tessere fogna con un tombino che porta all'obiettivo.
func tiles_for(objkey: String) -> Array:
	var out := []
	for key in tiles:
		if objkey in tiles[key]["tomb"]:
			out.append("c:" + key)
	return out


func board_ghouls() -> Array:
	var out := []
	for id in cs:
		var c: Dictionary = cs[id]
		if (c["t"] == "G" or c["t"] == "S") and (c["loc"].begins_with("c:") or c["loc"].begins_with("o:")):
			out.append(id)
	return out


func human_locs_with_ghouls() -> Array:
	var locs := {}
	for id in cs:
		var c: Dictionary = cs[id]
		if (c["t"] == "V" or c["t"] == "F") and (c["loc"].begins_with("c:") or c["loc"].begins_with("o:")):
			locs[c["loc"]] = true
	var out := []
	for l in locs:
		if not ghouls_at(l).is_empty():
			out.append(l)
	out.sort()
	return out


func obj_value(k: String) -> int:
	var s := 0
	for id in ids_at("o:" + k, "P"):
		s += int(cs[id]["v"])
	return s * int(D.OBJECTIVES[k]["mult"])


# ================================================================ spostamento delle pedine

func _move(id: int, loc: String) -> void:
	var c: Dictionary = cs[id]
	var old: String = c["loc"]
	if old == "":
		gpool.erase(id)
		hpool.erase(id)
	c["loc"] = loc
	if loc == "" :
		if is_ghoul(id):
			if not gpool.has(id):
				gpool.insert(rng.randi_range(0, gpool.size()), id)
		else:
			if not hpool.has(id):
				hpool.insert(rng.randi_range(0, hpool.size()), id)
	revealed.erase(id)


## Pesca un ghoul dal contenitore e lo mette in una locazione. -1 se il contenitore è vuoto.
func draw_ghoul_to(loc: String) -> int:
	if gpool.is_empty():
		return -1
	var id: int = gpool.pop_front()
	cs[id]["loc"] = loc
	if not humans_at(loc).is_empty() and not hatk.has(loc):
		gatk[loc] = true
	return id


# ================================================================ partita

func run() -> void:
	log_msg("— Inizia la partita: %d giocatori umani contro %s." % [nh, pname(0)])
	await _setup_game()
	while not game_over and not abort:
		turn_no += 1
		log_msg("═══ Turno %d ═══" % turn_no)
		await _turn_start()
		if game_over:
			break
		await _ghoul_phase()
		if game_over:
			break
		await _human_phase()
		await _combat_phase()
		_end_of_turn()
		changed.emit()
	_finish()


func _setup_game() -> void:
	phase = "setup"
	for i in START_GHOULS:
		draw_ghoul_to(covo_loc())
	log_msg("Il Ghoul pesca %d pedine e le mette coperte nel Covo." % START_GHOULS)
	var first := 1
	var need := 4 if nh == 2 else 6
	var drawn := []
	var vols := 0
	while vols < need and not hpool.is_empty():
		var id: int = hpool.pop_front()
		var c: Dictionary = cs[id]
		if c["t"] == "X":
			hpool.insert(rng.randi_range(0, hpool.size()), id)
			draw_ghoul_to(covo_loc())
			log_msg("%s pesca un Rinforzo ghoul: torna nel contenitore e un altro ghoul arriva nel Covo." % pname(first))
			continue
		c["o"] = first
		c["loc"] = "t:%d" % first
		drawn.append(id)
		if c["t"] == "V":
			vols += 1
	log_msg("%s pesca %d pedine Umani (%d volontari)." % [pname(first), drawn.size(), vols])
	changed.emit()
	# scelta degli obiettivi da approntare
	var r = await decide(first, {"type": "objs", "ctx": "setup_objs", "count": nh, "allowed": D.OBJ_ORDER.duplicate(),
		"title": "Scegli %d Obiettivi da approntare con le pedine pescate" % nh})
	var chosen := []
	if r is Array:
		for k in r:
			if str(k) in D.OBJECTIVES and not chosen.has(str(k)) and chosen.size() < nh:
				chosen.append(str(k))
	for k in D.OBJ_ORDER:
		if chosen.size() >= nh:
			break
		if not chosen.has(k):
			chosen.append(k)
	var r2 = await decide(first, {"type": "dist", "ctx": "setup_dist", "ids": drawn.duplicate(), "objs": chosen.duplicate(),
		"title": "Distribuisci le pedine pescate sugli Obiettivi"})
	for id in drawn:
		var k: String = chosen[0]
		if r2 is Dictionary and r2.has(id) and str(r2[id]) in chosen:
			k = str(r2[id])
		cs[id]["loc"] = "o:" + k
	# ognuno sceglie un obiettivo, l'ultimo resta a chi li ha approntati
	var left := chosen.duplicate()
	for s in range(2, nh + 1):
		var al := []
		for k in left:
			al.append("o:" + k)
		var pickd := await choose_loc(s, "setup_pick", "Scegli l'Obiettivo che difenderai", al)
		var k2 := pickd.substr(2)
		left.erase(k2)
		_give_obj(k2, s)
	_give_obj(left[0], first)
	for i in nh:
		pass
	log_msg("Gli Obiettivi sono pronti. Che la difesa abbia inizio!")
	changed.emit()


func _give_obj(k: String, s: int) -> void:
	objs[k]["owner"] = s
	for id in ids_at("o:" + k):
		if cs[id]["o"] >= 1:
			cs[id]["o"] = s
	log_msg("%s difende %s." % [pname(s), D.obj_name(k)])


func _turn_start() -> void:
	phase = "inizio"
	gatk = {}
	hatk = {}
	# Cimitero
	var cim := cimitero_loc()
	if cim != "":
		var n := ghouls_at(cim).size()
		var r := d6()
		dice = [r]
		_fx("dice", {"dice": [r], "who": 0})
		if r == 6 and n > 0:
			var g: Array = ghouls_at(cim)
			var id: int = g[rng.randi_range(0, g.size() - 1)]
			_move(id, "")
			log_msg("Cimitero: esce 6, un ghoul ritrova la Pace Eterna.")
		elif r <= n:
			if draw_ghoul_to(cim) >= 0:
				log_msg("Cimitero: esce %d (ghoul presenti %d), un altro ghoul si leva dalle tombe." % [r, n])
		else:
			log_msg("Cimitero: esce %d, nulla si muove fra le tombe." % r)
	# volontari nel Covo
	for s in range(1, nh + 1):
		var here := false
		for id in ids_at(covo_loc(), "V"):
			if cs[id]["o"] == s:
				here = true
		if not here:
			continue
		var gl := []
		for id in board_ghouls():
			var l: String = cs[id]["loc"]
			if not gl.has(l):
				gl.append(l)
		gl.sort()
		if gl.is_empty():
			continue
		var l2 := await choose_loc(s, "covo_kill", "Volontari nel Covo: scegli dove togliere una pedina ghoul", gl, true)
		if l2 == "":
			continue
		var g2: Array = ghouls_at(l2)
		var id2: int = g2[rng.randi_range(0, g2.size() - 1)]
		_move(id2, "")
		kills[s] += 1
		log_msg("%s, dal Covo, toglie dal gioco un ghoul (%s): +1 punto." % [pname(s), loc_name(l2)])
	changed.emit()


# ================================================================ fase del Ghoul

func ghoul_moves_from(loc: String) -> Array:
	var out := []
	if loc.begins_with("c:"):
		out.append_array(tile_neighbors(loc))
		if not tile_deck.is_empty():
			out.append_array(frontier_of(loc))
		for k in tombs_of(loc):
			var ol: String = "o:" + k
			if not out.has(ol):
				out.append(ol)
	elif loc.begins_with("o:"):
		out.append_array(tiles_for(loc.substr(2)))
	return out


func _ghoul_phase() -> void:
	phase = "ghoul"
	active_human = -1
	var a := d6()
	var b := d6()
	dice = [a, b]
	gmove_left = a + b
	moved = {}
	_fx("dice", {"dice": [a, b], "who": 0})
	log_msg("%s tira %d + %d: può muovere %d pedine ghoul." % [pname(0), a, b, gmove_left])
	var guard := 0
	while gmove_left > 0 and not game_over and guard < 60:
		guard += 1
		var movable := _gmovable()
		if movable.is_empty():
			break
		var r = await decide(0, {"type": "gmove", "ctx": "gmove", "left": gmove_left, "movable": movable,
			"title": "Muovi i ghoul: ancora %d pedine" % gmove_left})
		if not (r is Dictionary) or r.is_empty():
			break
		var to := str(r.get("to", ""))
		var ids := []
		for x in r.get("ids", []):
			var id := int(x)
			if cs.has(id) and is_ghoul(id) and not moved.has(id) and not ids.has(id):
				ids.append(id)
		if ids.is_empty():
			break
		var from: String = cs[ids[0]]["loc"]
		var ok := true
		for id in ids:
			if cs[id]["loc"] != from:
				ok = false
		if not ok or not (to in ghoul_moves_from(from)):
			continue
		ids = ids.slice(0, gmove_left)
		await _ghoul_go(ids, from, to)
		changed.emit()
	gmove_left = 0


## Pedine ghoul che possono ancora muovere: loc -> [id].
func _gmovable() -> Dictionary:
	var out := {}
	for id in board_ghouls():
		if moved.has(id):
			continue
		var l: String = cs[id]["loc"]
		if ghoul_moves_from(l).is_empty():
			continue
		if not out.has(l):
			out[l] = []
		out[l].append(id)
	return out


func _ghoul_go(ids: Array, from: String, to: String) -> void:
	if to.begins_with("c:") and not tiles.has(to.substr(2)):
		# esplorazione: si pesca una tessera e la si piazza in modo che i corridoi comunichino
		var kind: String = tile_deck.pop_front()
		var p := cell(to)
		var q := cell(from)
		var opts := placements_at(kind, p, q)
		var idx := 0
		if opts.size() > 1:
			var r = await decide(0, {"type": "tile", "ctx": "explore", "kind": kind, "options": opts, "from": from,
				"title": "Piazza la nuova tessera fogna"})
			idx = clampi(int(r) if (r is int or r is float) else 0, 0, opts.size() - 1)
		_place_tile(kind, opts[idx][0], opts[idx][1], opts[idx][2], 0)
	for id in ids:
		cs[id]["loc"] = to
		moved[id] = true
	gmove_left -= ids.size()
	if not humans_at(to).is_empty() and not hatk.has(to):
		gatk[to] = true
	log_msg("%s muove %d ghoul: %s → %s." % [pname(0), ids.size(), loc_name(from), loc_name(to)])
	_fx("move", {"ids": ids, "from": from, "to": to})
	if to.begins_with("o:"):
		var k := to.substr(2)
		if not ghoul_known.has(k):
			ghoul_known[k] = true
			log_msg("Il Ghoul scopre che quel tombino porta a %s." % D.obj_name(k))
		_trigger_mines(to)


func _trigger_mines(loc: String) -> void:
	for mid in ids_at(loc, "M"):
		var v: int = cs[mid]["v"]
		var g: Array = ghouls_at(loc)
		var killed := 0
		for i in v:
			if g.is_empty():
				break
			var id: int = g.pop_at(rng.randi_range(0, g.size() - 1))
			_move(id, "")
			killed += 1
		var own: int = cs[mid]["o"]
		_move(mid, "out")
		if own >= 1:
			kills[own] += killed
		log_msg("BOOM! Una mina da %d esplode a %s: %d ghoul eliminati." % [v, loc_name(loc), killed])
		_fx("mine", {"loc": loc, "v": v})


## Rotazioni possibili per una tessera nella casella p entrando da q: i corridoi devono comunicare
## con q e, per quanto possibile, con le altre tessere vicine.
func placements_at(kind: String, p: Vector2i, q: Vector2i) -> Array:
	var best := 99
	var opts := []
	for rot in 4:
		var m := D.open_mask(kind, rot)
		var dq := D.DIRS.find(q - p)
		if dq < 0 or m & (1 << dq) == 0:
			continue
		var mis := _mismatch(m, p)
		if mis < best:
			best = mis
			opts = []
		if mis == best:
			opts.append([p.x, p.y, rot])
	return opts


func _mismatch(m: int, p: Vector2i) -> int:
	var mis := 0
	for d in 4:
		var n: Vector2i = p + D.DIRS[d]
		var nk := "%d,%d" % [n.x, n.y]
		if not tiles.has(nk):
			continue
		var a := m & (1 << d) != 0
		var b := tile_mask(nk) & (1 << ((d + 2) % 4)) != 0
		if a != b:
			mis += 1
	return mis


## Piazzamenti possibili per i giocatori umani: una casella vuota accanto a un corridoio aperto,
## con la tessera girata in modo da comunicare con almeno una tessera già presente.
func human_placements(kind: String) -> Array:
	var cells := {}
	for key in tiles:
		for f in frontier_of("c:" + key):
			cells[f] = true
	var opts := []
	var keys := cells.keys()
	keys.sort()
	for f in keys:
		var p := cell(f)
		for rot in 4:
			var m := D.open_mask(kind, rot)
			var conn := false
			for d in 4:
				var n: Vector2i = p + D.DIRS[d]
				var nk := "%d,%d" % [n.x, n.y]
				if tiles.has(nk) and m & (1 << d) != 0 and tile_mask(nk) & (1 << ((d + 2) % 4)) != 0:
					conn = true
			if conn:
				opts.append([p.x, p.y, rot])
	return opts


func _place_tile(kind: String, x: int, y: int, rot: int, by: int) -> void:
	var tomb := []
	for i in D.TILES[kind]["tomb"]:
		tomb.append(loc_tokens.pop_front() if not loc_tokens.is_empty() else "")
	tiles["%d,%d" % [x, y]] = {"k": kind, "r": rot, "tomb": tomb}
	var who := pname(by)
	log_msg("%s piazza una tessera fogna: %s%s." % [who, D.TILES[kind]["name"],
		"" if tomb.is_empty() else " (%d tombin%s)" % [tomb.size(), "o" if tomb.size() == 1 else "i"]])
	_fx("tile", {"x": x, "y": y})


# ================================================================ fase degli Umani

func _human_phase() -> void:
	phase = "numeri"
	played = {}
	for s in range(1, nh + 1):
		if tokens_used[s].size() >= 5:
			tokens_used[s] = []
		var av := []
		for v in range(1, 6):
			if not tokens_used[s].has(v):
				av.append(v)
		var r = await decide(s, {"type": "token", "ctx": "token", "options": av, "secret": true,
			"title": "Scegli in segreto il segnalino numerato"})
		var v2: int = int(r) if (r is int or r is float) else av[0]
		if not av.has(v2):
			v2 = av[0]
		played[s] = v2
		tokens_used[s].append(v2)
	var parts := []
	for s in played:
		parts.append("%s %d" % [pname(s), played[s]])
	log_msg("Segnalini rivelati: " + ", ".join(parts) + ".")
	_fx("tokens", {"played": played.duplicate()})
	# chi ha giocato lo stesso numero salta il turno; il più alto non muove
	var count := {}
	for s in played:
		count[played[s]] = count.get(played[s], 0) + 1
	var actors := []
	var hi := -1
	for s in played:
		if count[played[s]] == 1:
			actors.append(s)
			hi = maxi(hi, played[s])
	for s in played:
		if count[played[s]] > 1:
			log_msg("%s salta il turno (numero uguale a un altro)." % pname(s))
	var real := []
	for s in actors:
		if played[s] == hi:
			log_msg("%s ha il numero più alto e resta fermo." % pname(s))
		else:
			real.append(s)
	real.sort_custom(func(a, b): return played[a] < played[b])
	for i in real.size():
		await _human_turn(real[i], played[real[i]], i == 0)
		if game_over:
			return
	active_human = -1


func _human_turn(s: int, num: int, first: bool) -> void:
	phase = "umano"
	active_human = s
	log_msg("— Muove %s (segnalino %d)." % [pname(s), num])
	# tessera fogna (solo chi ha giocato il numero più basso)
	if first and not tile_deck.is_empty():
		var kind: String = tile_deck[0]
		var opts := human_placements(kind)
		if not opts.is_empty():
			tile_deck.pop_front()
			var r = await decide(s, {"type": "tile", "ctx": "hplace", "kind": kind, "options": opts,
				"title": "Piazza la tessera fogna pescata"})
			var idx := clampi(int(r) if (r is int or r is float) else 0, 0, opts.size() - 1)
			_place_tile(kind, opts[idx][0], opts[idx][1], opts[idx][2], s)
			changed.emit()
	# pedine Umani
	var folla := []
	var drawn := 0
	for i in num:
		if hpool.is_empty():
			log_msg("Il contenitore delle pedine Umani è vuoto.")
			break
		var id: int = hpool.pop_front()
		var c: Dictionary = cs[id]
		drawn += 1
		match c["t"]:
			"X":
				hpool.insert(rng.randi_range(0, hpool.size()), id)
				var g := draw_ghoul_to(covo_loc())
				log_msg("%s pesca un Rinforzo ghoul! Torna nel contenitore%s." % [pname(s), " e un ghoul arriva nel Covo" if g >= 0 else ""])
				_fx("reinforce", {})
			"V":
				if _vol_lost(c["k"]):
					c["loc"] = "out"
					log_msg("%s pesca %s: il loro obiettivo è devastato, escono dal gioco." % [pname(s), D.vol_name(c["k"])])
				else:
					c["o"] = s
					c["loc"] = "t:%d" % s
					log_msg("%s pesca: %s." % [pname(s), cname(id)])
			"F":
				c["o"] = s
				c["loc"] = "t:%d" % s
				folla.append(id)
			_:
				c["o"] = s
				c["loc"] = "t:%d" % s
				log_msg("%s pesca: %s." % [pname(s), cname(id)])
	changed.emit()
	for id in folla:
		var al := []
		for k in D.OBJ_ORDER:
			if not objs[k]["dev"]:
				al.append("o:" + k)
		var l := await choose_loc(s, "folla", "Pescata una Folla: su quale Obiettivo la metti?", al)
		cs[id]["loc"] = l
		if not ghouls_at(l).is_empty() and not gatk.has(l):
			hatk[l] = true
		log_msg("%s manda la Folla a %s." % [pname(s), loc_name(l)])
		changed.emit()
	# movimento
	moved = {}
	main_move_used = false
	radio_used = {}
	var guard := 0
	while not game_over and guard < 30:
		guard += 1
		var mv := hmovable(s)
		if mv.is_empty():
			break
		var r = await decide(s, {"type": "hmove", "ctx": "hmove", "movable": mv, "main_used": main_move_used,
			"title": "Muovi un gruppo di volontari" if not main_move_used else "Muovi i gruppi con la Radio"})
		if not (r is Dictionary) or r.is_empty():
			break
		if not _apply_hmove(s, r):
			continue
		changed.emit()
	phase = "umano_fine"


func _vol_lost(k: String) -> bool:
	for ok in objs:
		if objs[ok]["dev"] and k in D.OBJECTIVES[ok]["vol"]:
			return true
	return false


## Gruppi che il giocatore può ancora muovere: loc -> {"vol": [id], "items": [id], "radio": bool, "to": [loc]}.
func hmovable(s: int) -> Dictionary:
	var out := {}
	for id in cs:
		var c: Dictionary = cs[id]
		if c["t"] != "V" or c["o"] != s or moved.has(id):
			continue
		var l: String = c["loc"]
		if not (l.begins_with("t:") or l.begins_with("o:") or l.begins_with("c:")):
			continue
		if not out.has(l):
			out[l] = {"vol": [], "items": [], "radio": false, "to": human_moves_from(s, l)}
		out[l]["vol"].append(id)
	for l in out.keys():
		var radio := false
		for rid in ids_at(l, "R"):
			if cs[rid]["o"] == s and not radio_used.has(rid) and not moved.has(rid):
				radio = true
		out[l]["radio"] = radio
		if main_move_used and not radio:
			out.erase(l)
			continue
		if out[l]["to"].is_empty():
			out.erase(l)
			continue
		var items := []
		for iid in ids_at(l, "PMR"):
			if cs[iid]["o"] == s and not moved.has(iid):
				if cs[iid]["t"] == "R" or l.begins_with("t:"):
					items.append(iid)
		out[l]["vol"].sort()
		out[l]["items"] = items
	return out


func human_moves_from(s: int, loc: String) -> Array:
	var out := []
	if loc.begins_with("t:"):
		for k in D.OBJ_ORDER:
			if not objs[k]["dev"]:
				out.append("o:" + k)
	elif loc.begins_with("o:"):
		out.append("t:%d" % s)
		out.append_array(tiles_for(loc.substr(2)))
	elif loc.begins_with("c:"):
		out.append_array(tile_neighbors(loc))
		for k in tombs_of(loc):
			if not objs[k]["dev"]:
				out.append("o:" + k)
	return out


func _apply_hmove(s: int, r: Dictionary) -> bool:
	var to := str(r.get("to", ""))
	var ids := []
	for x in r.get("ids", []):
		var id := int(x)
		if cs.has(id) and not ids.has(id) and not moved.has(id):
			ids.append(id)
	var mv := hmovable(s)
	var vols := []
	var items := []
	var from := ""
	for id in ids:
		var c: Dictionary = cs[id]
		if from == "":
			from = c["loc"]
		if c["loc"] != from or not mv.has(from):
			return false
		if c["t"] == "V" and c["o"] == s:
			vols.append(id)
		elif id in mv[from]["items"]:
			items.append(id)
	if vols.is_empty() or not (to in mv[from]["to"]):
		return false
	# al massimo una Mina o un Punto Vittoria per volontario; le radio viaggiano libere
	var carried := 0
	var keep := []
	var radio_id := -1
	for iid in items:
		if cs[iid]["t"] == "R":
			keep.append(iid)
			if radio_id < 0 and not radio_used.has(iid):
				radio_id = iid
		elif carried < vols.size() and to.begins_with("o:"):
			keep.append(iid)
			carried += 1
	# un gruppo con la Radio usa il movimento della radio, gli altri il movimento normale
	if radio_id >= 0:
		radio_used[radio_id] = true
	elif not main_move_used:
		main_move_used = true
	else:
		return false
	for id in vols + keep:
		cs[id]["loc"] = to
		moved[id] = true
	if not ghouls_at(to).is_empty() and not gatk.has(to):
		hatk[to] = true
	if to.begins_with("o:"):
		var k := to.substr(2)
		var others := false
		for id in ids_at(to, "V"):
			if cs[id]["o"] != s:
				others = true
		if not others and objs[k]["owner"] != s:
			var prev: int = objs[k]["owner"]
			objs[k]["owner"] = s
			log_msg("%s prende il controllo di %s%s." % [pname(s), D.obj_name(k), "" if prev < 1 else " (prima di %s)" % pname(prev)])
	log_msg("%s muove %d volontar%s%s: %s → %s." % [pname(s), vols.size(), "io" if vols.size() == 1 else "i",
		"" if keep.is_empty() else " con %d pedin%s" % [keep.size(), "a" if keep.size() == 1 else "e"], loc_name(from), loc_name(to)])
	_fx("move", {"ids": vols + keep, "from": from, "to": to})
	return true


# ================================================================ combattimenti

func _combat_phase() -> void:
	phase = "combattimento"
	var locs := human_locs_with_ghouls()
	while not locs.is_empty() and not game_over:
		var l := locs[0] as String
		if locs.size() > 1:
			l = await choose_loc(0, "combat_order", "Scegli dove risolvere il prossimo combattimento", locs)
		await _resolve_combat(l)
		locs = human_locs_with_ghouls()
	combat = {}
	revealed = {}


## Chi comanda i difensori in una locazione: il padrone dell'obiettivo se ha volontari lì,
## altrimenti chi ha più pedine.
func commander(loc: String) -> int:
	var cnt := {}
	for id in humans_at(loc):
		var o: int = cs[id]["o"]
		if cs[id]["t"] == "V":
			cnt[o] = cnt.get(o, 0) + 2
		else:
			cnt[o] = cnt.get(o, 0) + 1
	if loc.begins_with("o:"):
		var ow: int = objs[loc.substr(2)]["owner"]
		if ow >= 1 and cnt.has(ow):
			return ow
	var best := -1
	var bv := -1
	for o in cnt:
		if o >= 1 and (cnt[o] > bv or (cnt[o] == bv and o < best)):
			best = o
			bv = cnt[o]
	return best if best >= 1 else 1


func _resolve_combat(loc: String) -> void:
	revealed = {}
	var surprise := false
	var sids := ids_at(loc, "S")
	if not sids.is_empty():
		surprise = gatk.has(loc)
		for id in sids:
			_move(id, "")
		log_msg("Fra i ghoul a %s c'è la pedina Sorpresa%s." % [loc_name(loc), ": attaccano per primi!" if surprise else ", ma sono gli Umani ad attaccare: viene scartata"])
	combat = {"loc": loc, "round": 0, "surprise": surprise, "last": []}
	log_msg("⚔ Combattimento a %s." % loc_name(loc))
	_fx("combat", {"loc": loc})
	changed.emit()
	var cmd := commander(loc)
	if humans_at(loc).is_empty() or ghouls_at(loc).is_empty():
		combat = {}
		return
	if not surprise:
		var shooters := []
		for id in humans_at(loc):
			if hranged(id) >= 0:
				shooters.append(id)
		if not shooters.is_empty():
			combat["step"] = "ranged"
			changed.emit()
			var att = await _ask_attacks(cmd, loc, "ranged", shooters, ghouls_at(loc))
			for grp in att:
				await _resolve_attack(loc, grp[0], grp[1], "ranged")
	var turn_g := surprise
	var rounds := 0
	while not humans_at(loc).is_empty() and not ghouls_at(loc).is_empty() and rounds < 200:
		rounds += 1
		combat["round"] = rounds
		if turn_g:
			combat["step"] = "gmelee"
			changed.emit()
			var att = await _ask_attacks(0, loc, "gmelee", ghouls_at(loc), humans_at(loc))
			for grp in att:
				await _resolve_attack(loc, grp[1], grp[0], "gmelee")
		else:
			combat["step"] = "hmelee"
			changed.emit()
			cmd = commander(loc)
			var att2 = await _ask_attacks(cmd, loc, "hmelee", humans_at(loc), ghouls_at(loc))
			for grp in att2:
				await _resolve_attack(loc, grp[0], grp[1], "hmelee")
		turn_g = not turn_g
	if humans_at(loc).is_empty():
		log_msg("A %s i difensori sono stati sopraffatti." % loc_name(loc))
	else:
		log_msg("A %s i ghoul sono stati respinti!" % loc_name(loc))
	revealed = {}
	combat = {}
	changed.emit()


## Chiede l'assegnazione degli attacchi e la rende valida: gruppi disgiunti; nel corpo a corpo ogni
## attaccante deve attaccare.
func _ask_attacks(seat: int, loc: String, mode: String, atk: Array, tgt: Array) -> Array:
	var req := {"type": "attacks", "ctx": mode, "mode": mode, "loc": loc, "atk": atk.duplicate(), "tgt": tgt.duplicate(),
		"title": {"ranged": "Tiro da lontano: assegna i tiratori ai ghoul", "hmelee": "Corpo a corpo degli Umani: assegna gli attacchi",
			"gmelee": "Corpo a corpo dei Ghoul: assegna gli attacchi"}[mode]}
	var r = await decide(seat, req)
	var used_a := {}
	var used_t := {}
	var out := []
	if r is Array:
		for g in r:
			if not (g is Array) or g.size() < 2 or not (g[0] is Array) or not (g[1] is Array):
				continue
			var a := []
			var t := []
			for x in g[0]:
				var id := int(x)
				if id in atk and not used_a.has(id):
					a.append(id)
			for x in g[1]:
				var id := int(x)
				if id in tgt and not used_t.has(id):
					t.append(id)
			if a.is_empty() or t.is_empty():
				continue
			for id in a:
				used_a[id] = true
			for id in t:
				used_t[id] = true
			out.append([a, t])
	if mode != "ranged":
		# chi è rimasto senza bersaglio si unisce al primo attacco (o ne apre uno nuovo)
		for id in atk:
			if used_a.has(id):
				continue
			var free := []
			for t in tgt:
				if not used_t.has(t):
					free.append(t)
			if not free.is_empty():
				used_t[free[0]] = true
				out.append([[id], [free[0]]])
			elif not out.is_empty():
				out[0][0].append(id)
			used_a[id] = true
	return out


## h = pedine umane, g = pedine ghoul. mode: ranged / hmelee / gmelee (chi attacca è indicato dal mode).
func _resolve_attack(loc: String, h: Array, g: Array, mode: String) -> void:
	var hs := []
	var gs := []
	for id in h:
		if cs.has(id) and cs[id]["loc"] == loc:
			hs.append(id)
	for id in g:
		if cs.has(id) and cs[id]["loc"] == loc:
			gs.append(id)
	if hs.is_empty() or gs.is_empty():
		return
	var hsum := 0
	for id in hs:
		hsum += maxi(0, hranged(id)) if mode == "ranged" else hmelee(id)
	var gsum := 0
	for id in gs:
		gsum += gval(id)
		revealed[id] = true
	var hd := d6()
	var gd := d6()
	var ht := hsum + hd
	var gt := gsum + gd
	var hn := []
	for id in hs:
		hn.append(cname(id))
	var gn := []
	for id in gs:
		gn.append(str(gval(id)))
	var what: String = {"ranged": "tiro da lontano", "hmelee": "attacco degli Umani", "gmelee": "attacco dei Ghoul"}[mode]
	var line := "%s: %s (%d+%d=%d) contro ghoul %s (%d+%d=%d)" % [what, ", ".join(hn), hsum, hd, ht, "+".join(gn), gsum, gd, gt]
	var outcome := ""
	var owner := _attack_owner(hs)
	if ht > gt:
		for id in gs:
			_move(id, "")
		kills[owner] += gs.size()
		outcome = "ghoul eliminati" if gs.size() > 1 else "ghoul eliminato"
	elif mode == "ranged":
		outcome = "nessun effetto"
	elif gt > ht:
		for id in hs:
			_move(id, "out")
		outcome = "umani fatti a pezzi"
	else:
		var nn := 0
		for id in hs:
			_move(id, "out")
			if draw_ghoul_to(loc) >= 0:
				nn += 1
		outcome = "parità: gli umani diventano ghoul (%d)" % nn
	log_msg(line + " → " + outcome + ".")
	combat["last"] = [{"mode": mode, "h": hn, "g": gn, "hs": hsum, "hd": hd, "gs": gsum, "gd": gd, "out": outcome}]
	_fx("attack", {"mode": mode, "hd": hd, "gd": gd, "ht": ht, "gt": gt, "out": outcome, "loc": loc})
	changed.emit()
	if ai_delay > 0.0 and not headless and is_inside_tree():
		await get_tree().create_timer(ai_delay * 0.8).timeout


func _attack_owner(hs: Array) -> int:
	var best := -1
	var bv := -99
	for id in hs:
		var v := hmelee(id) + (10 if cs[id]["t"] == "V" else 0)
		if v > bv and int(cs[id]["o"]) >= 1:
			bv = v
			best = cs[id]["o"]
	return best if best >= 1 else 1


# ================================================================ fine del turno

func _end_of_turn() -> void:
	phase = "fine"
	for k in D.OBJ_ORDER:
		var o: Dictionary = objs[k]
		if o["dev"]:
			continue
		var l: String = "o:" + k
		if ghouls_at(l).is_empty() or not humans_at(l).is_empty():
			continue
		o["dev"] = true
		for rid in ids_at(l, "R"):
			_move(rid, "out")
		var n: int = D.OBJECTIVES[k]["dev"]
		var drawn := 0
		for i in n:
			if draw_ghoul_to(l) >= 0:
				drawn += 1
		log_msg("☠ %s è DEVASTATO dai ghoul%s." % [D.obj_name(k), "" if drawn == 0 else ": arrivano altri %d ghoul" % drawn])
		_fx("devastated", {"obj": k})
		if k == "cattedrale":
			_end("ghoul", "La Cattedrale è caduta: i Ghouls hanno conquistato la città.")
			return
	if board_ghouls().is_empty():
		_end("umani", "Tutti i ghoul sono stati annientati!")
		return
	if tile_deck.is_empty() and not _ghouls_can_reach():
		_end("umani", "Le gallerie sono chiuse: i Ghouls non possono più raggiungere la città!")
		return
	var held := false
	for id in ids_at(covo_loc(), "V"):
		held = true
	if held:
		covo_streak += 1
		log_msg("I volontari occupano il Covo (%d/%d turni)." % [covo_streak, COVO_TURNS])
		if covo_streak >= COVO_TURNS:
			_end("umani", "Gli Umani hanno occupato il Covo per %d turni consecutivi!" % COVO_TURNS)
			return
	else:
		covo_streak = 0
	if max_turns > 0 and turn_no >= max_turns:
		_end("umani", "La città ha resistito per %d turni: i Ghouls si ritirano nelle fogne." % max_turns)


## Con il mazzo delle tessere finito: c'è ancora un ghoul che può arrivare a un obiettivo intatto?
func _ghouls_can_reach() -> bool:
	var seen := {}
	var q := []
	for id in board_ghouls():
		var l: String = cs[id]["loc"]
		if l.begins_with("o:"):
			for t in tiles_for(l.substr(2)):
				if not seen.has(t):
					seen[t] = true
					q.append(t)
		elif not seen.has(l):
			seen[l] = true
			q.append(l)
	var i := 0
	while i < q.size():
		var cur: String = q[i]
		i += 1
		for k in tombs_of(cur):
			if not objs[k]["dev"]:
				return true
		for n in tile_neighbors(cur):
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	return false


func _end(w: String, why: String) -> void:
	game_over = true
	winner = w
	end_reason = why
	log_msg("■ " + why)


func score(s: int) -> Dictionary:
	var pos := 0
	var neg := 0
	for k in objs:
		if objs[k]["owner"] != s:
			continue
		if objs[k]["dev"]:
			neg += obj_value(k)
		else:
			pos += obj_value(k)
	var tot := -neg
	if winner == "umani":
		tot = pos + kills[s] - neg
	return {"seat": s, "pos": pos, "kills": kills[s], "neg": neg, "total": tot}


func _finish() -> void:
	results = []
	for s in range(1, nh + 1):
		results.append(score(s))
	results.sort_custom(func(a, b): return a["total"] > b["total"])
	if not results.is_empty() and game_over:
		var parts := []
		for r in results:
			parts.append("%s %d" % [pname(r["seat"]), r["total"]])
		log_msg("Punteggi: " + ", ".join(parts) + ".")
	phase = "fine_partita"
	changed.emit()
	game_ended.emit(results)


## Impronta della partita (per verificare che due dispositivi online abbiano giocato la stessa).
func fingerprint() -> String:
	var parts := [str(turn_no), winner]
	for id in cs:
		parts.append("%d%s" % [id, cs[id]["loc"]])
	for key in tiles:
		parts.append(key + tiles[key]["k"] + str(tiles[key]["r"]))
	return str(hash("|".join(parts))) + " t%d %s" % [turn_no, winner]

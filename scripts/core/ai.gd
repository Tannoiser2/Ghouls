class_name GHAI
extends RefCounted
## IA di Ghouls, per il giocatore Ghoul e per i giocatori Umani.
## Gioca lealmente: il Ghoul non sa dove portano i tombini che non ha ancora attraversato né cosa c'è
## sotto le pedine coperte degli Obiettivi (ne vede solo il numero); gli Umani non conoscono la forza
## dei ghoul finché non si scoprono in combattimento.
## Livelli: 0 = facile, 1 = normale, 2 = difficile.

const D = preload("res://scripts/data/gh_data.gd")
const AVG_GHOUL := 2.2

var level := 1
var rng := RandomNumberGenerator.new()
static var _pwin := {}


func _init(lvl := 1, seed := 1) -> void:
	level = lvl
	rng.seed = seed


func decide(e: GHEngine, s: int, req: Dictionary):
	match req["type"]:
		"pick":
			return 0
		"token":
			return _token(e, s, req)
		"loc":
			return _loc(e, s, req)
		"tile":
			return _tile(e, s, req)
		"gmove":
			return _gmove(e, req)
		"hmove":
			return _hmove(e, s, req)
		"objs":
			return _setup_objs(e, s, req)
		"dist":
			return _setup_dist(e, s, req)
		"attacks":
			return _attacks(e, s, req)
	return null


func _noise(x: float) -> float:
	var amp: float = [6.0, 2.0, 0.6][clampi(level, 0, 2)]
	return x + rng.randf_range(-amp, amp)


# ================================================================ probabilità

## Probabilità che a + d6 superi b + d6, che pareggi, che perda.
static func p_attack(a: float, b: float) -> Vector3:
	var diff := int(round(a - b))
	if _pwin.has(diff):
		return _pwin[diff]
	var w := 0
	var t := 0
	for x in range(1, 7):
		for y in range(1, 7):
			if diff + x > y:
				w += 1
			elif diff + x == y:
				t += 1
	var r := Vector3(w / 36.0, t / 36.0, (36 - w - t) / 36.0)
	_pwin[diff] = r
	return r


# ================================================================ mappa

## Distanze (in tessere) da un insieme di tessere di partenza, lungo i corridoi.
func _bfs(e: GHEngine, starts: Array) -> Dictionary:
	var dist := {}
	var q := []
	for s in starts:
		if not dist.has(s):
			dist[s] = 0
			q.append(s)
	var i := 0
	while i < q.size():
		var cur: String = q[i]
		i += 1
		for n in e.tile_neighbors(cur):
			if not dist.has(n):
				dist[n] = dist[cur] + 1
				q.append(n)
	return dist


## Minaccia sugli obiettivi (per gli Umani, che conoscono i tombini): ghoul vicini ai tombini.
func _threat(e: GHEngine) -> Dictionary:
	var out := {}
	var stacks := {}
	for id in e.board_ghouls():
		var l: String = e.cs[id]["loc"]
		stacks[l] = stacks.get(l, 0) + 1
	for k in D.OBJ_ORDER:
		var t := 0.0
		var tl := e.tiles_for(k)
		if not tl.is_empty():
			var dist := _bfs(e, tl)
			for l in stacks:
				if l.begins_with("c:") and dist.has(l):
					t += stacks[l] * AVG_GHOUL / (1.0 + dist[l])
				elif l.begins_with("o:") and l != "o:" + k:
					var best := 99
					for tt in e.tiles_for(l.substr(2)):
						if dist.has(tt):
							best = mini(best, dist[tt] + 1)
					if best < 99:
						t += stacks[l] * AVG_GHOUL / (1.0 + best)
		out[k] = t
	return out


func _defense(e: GHEngine, loc: String) -> float:
	var d := 0.0
	for id in e.humans_at(loc):
		d += e.hmelee(id) + 0.6
	return d


# ================================================================ Ghoul

## Valore di arrivo per il Ghoul, per tessera.
func _ghoul_potential(e: GHEngine) -> Dictionary:
	var targets := []   # [tile loc, valore]
	# forza massima che si può portare in un turno (al più 12 pedine si muovono)
	var vals := []
	for id in e.board_ghouls():
		vals.append(e.gval(id))
	vals.sort()
	vals.reverse()
	var reach := 0.0
	for i in mini(10, vals.size()):
		reach += vals[i]
	for key in e.tiles:
		var l: String = "c:" + key
		var t: Dictionary = e.tiles[key]
		for k in t["tomb"]:
			if k == "":
				continue
			if e.ghoul_known.has(k):
				if not e.objs[k]["dev"]:
					var tv: float = 60.0 if k == "cattedrale" else 22.0 + 4.0 * D.OBJECTIVES[k]["mult"]
					var late := e.max_turns > 0 and e.max_turns - e.turn_no <= 4
					if _defense(e, "o:" + k) * 1.1 + 2.0 > reach and level >= 1 and not late:
						tv = 6.0    # una fortezza: meglio cercare altrove
					targets.append([l, tv])
			else:
				targets.append([l, 26.0])
		if not e.tile_deck.is_empty() and not e.frontier_of(l).is_empty():
			targets.append([l, 9.0])
		if not e.humans_at(l).is_empty():
			targets.append([l, 14.0])
	var pot := {}
	for tg in targets:
		var dist := _bfs(e, [tg[0]])
		for l in dist:
			var v: float = tg[1] - 5.0 * dist[l]
			if v > pot.get(l, -99.0):
				pot[l] = v
	return pot


func _gstrength(e: GHEngine, ids: Array) -> float:
	var s := 0.0
	for id in ids:
		s += e.gval(id)
	return s


func _gmove(e: GHEngine, req: Dictionary) -> Dictionary:
	var movable: Dictionary = req["movable"]
	var left: int = req["left"]
	var pot := _ghoul_potential(e)
	var best := {}
	var best_v := 0.5
	var cim := e.cimitero_loc()
	for l in movable:
		var ids: Array = movable[l].duplicate()
		ids.sort_custom(func(a, b): return e.gval(a) > e.gval(b))
		var here := e.ghouls_at(l).size()
		# qualche ghoul resta nel Cimitero a evocarne altri, e uno a guardia del Covo
		var keep := 0
		if l == cim:
			keep = mini(3, here)
		elif l == e.covo_loc() and level >= 1:
			keep = 1 if here > 2 else 0
		var avail := ids.slice(0, maxi(0, ids.size() - keep))
		if avail.is_empty():
			continue
		var base: float = pot.get(l, -20.0)
		if l.begins_with("o:"):
			base = -10.0
		for to in e.ghoul_moves_from(l):
			var group := avail.slice(0, left)
			var v := 0.0
			if to.begins_with("o:"):
				var k: String = to.substr(2)
				if e.objs[k]["dev"]:
					continue
				var pieces := e.ids_at(to).size()
				# le pedine sui Trasporti sono scoperte: il Ghoul sa più o meno chi è entrato negli
				# obiettivi; ne stima la forza con un margine d'errore
				var defense := _defense(e, to) * rng.randf_range(0.9, 1.25) + pieces * 0.2
				var str_ := _gstrength(e, group) + _gstrength(e, e.ghouls_at(to))
				var known := e.ghoul_known.has(k)
				var val: float = 60.0 if (known and k == "cattedrale") else (30.0 + 5.0 * D.OBJECTIVES[k]["mult"] if known else 30.0)
				if pieces == 0:
					v = val + 10.0
				elif str_ >= defense * [0.8, 1.15, 1.05][level] + 2.0 or (e.max_turns > 0 and e.max_turns - e.turn_no <= 2 and level >= 1):
					v = val
				elif group.size() >= 12 and str_ >= defense * 0.8:
					v = val * 0.6
				else:
					# aspettiamo rinforzi sulla tessera del tombino
					continue
			elif not e.tiles.has(to.substr(2)):
				v = 10.0 - base * 0.3
				group = avail.slice(0, mini(left, maxi(1, avail.size() / 2)))
			else:
				var hum := e.humans_at(to)
				var p2: float = pot.get(to, -20.0)
				if not hum.is_empty():
					var hd := _defense(e, to)
					if _gstrength(e, group) + _gstrength(e, e.ghouls_at(to)) < hd * 1.2 + 2.0:
						continue
					p2 += 8.0
				v = p2 - base
			v = _noise(v) * (1.0 + 0.08 * group.size())
			if v > best_v:
				best_v = v
				best = {"ids": group, "to": to}
	return best


func _tile(e: GHEngine, s: int, req: Dictionary) -> int:
	var opts: Array = req["options"]
	var kind: String = req["kind"]
	var covo_d := _bfs(e, [e.covo_loc()])
	var best := 0
	var bv := -1e9
	for i in opts.size():
		var o: Array = opts[i]
		var p := Vector2i(o[0], o[1])
		var m := D.open_mask(kind, o[2])
		var newf := 0
		var closed := 0
		var conn := 0
		for d in 4:
			var n: Vector2i = p + D.DIRS[d]
			var nk := "%d,%d" % [n.x, n.y]
			var open := m & (1 << d) != 0
			if e.tiles.has(nk):
				var their := e.tile_mask(nk) & (1 << ((d + 2) % 4)) != 0
				if their and not open:
					closed += 1
				if their and open:
					conn += 1
			elif open:
				newf += 1
		var v := 0.0
		if s == 0:
			v = newf * 3.0 + D.TILES[kind]["tomb"] * 2.0
		else:
			# gli Umani cercano di chiudere le gallerie e tenere lontani i tombini dal Covo
			var dc := 99
			for d in 4:
				var n: Vector2i = p + D.DIRS[d]
				var cl := GHEngine.cloc(n)
				if covo_d.has(cl):
					dc = mini(dc, covo_d[cl] + 1)
			v = -newf * 3.0 + closed * 4.0 - conn * 0.5
			if D.TILES[kind]["tomb"] > 0:
				v += minf(dc, 8) * 2.0
			else:
				v -= minf(dc, 8) * 0.5
		v = _noise(v)
		if v > bv:
			bv = v
			best = i
	return best


# ================================================================ Umani

func _token(e: GHEngine, s: int, req: Dictionary) -> int:
	var av: Array = req["options"]
	var thr := _threat(e)
	var danger := 0.0
	for k in D.OBJ_ORDER:
		if e.objs[k]["owner"] == s or k == "cattedrale":
			danger += thr[k]
	var w := []
	var tot := 0.0
	for v in av:
		var x := 1.0
		if v == 1:
			x = 0.7 + danger * 0.15
		elif v == 5:
			x = 0.6
		elif v >= 3:
			x = 1.3
		if level == 0:
			x = 1.0
		w.append(x)
		tot += x
	var r := rng.randf() * tot
	for i in av.size():
		r -= w[i]
		if r <= 0:
			return av[i]
	return av[av.size() - 1]


func _loc(e: GHEngine, s: int, req: Dictionary) -> String:
	var al: Array = req["allowed"]
	match req["ctx"]:
		"combat_order":
			return al[0]
		"setup_pick":
			var best: String = al[0]
			var bv := -1e9
			for l in al:
				var v := 0.0
				for id in e.ids_at(l):
					var c: Dictionary = e.cs[id]
					v += e.hmelee(id) + (c["v"] * D.OBJECTIVES[l.substr(2)]["mult"] if c["t"] == "P" else 0)
				v = _noise(v)
				if v > bv:
					bv = v
					best = l
			return best
		"folla":
			var thr := _threat(e)
			var best2: String = al[0]
			var bv2 := -1e9
			for l in al:
				var k: String = l.substr(2)
				var v: float = thr[k] * (3.0 if k == "cattedrale" else 1.0)
				if e.objs[k]["owner"] == s:
					v += 2.0 + thr[k]
				v -= _defense(e, l) * 0.3
				v = _noise(v)
				if v > bv2:
					bv2 = v
					best2 = l
			return best2
		"covo_kill":
			var thr2 := _threat(e)
			var best3: String = al[0]
			var bv3 := -1e9
			for l in al:
				var v: float = e.ghouls_at(l).size() * 0.5
				if l.begins_with("o:"):
					v += 3.0
				for k in e.tombs_of(l):
					v += 4.0 if (e.objs[k]["owner"] == s or k == "cattedrale") else 1.0
				v = _noise(v)
				if v > bv3:
					bv3 = v
					best3 = l
			return best3
	return al[rng.randi_range(0, al.size() - 1)]


func _setup_objs(e: GHEngine, s: int, req: Dictionary) -> Array:
	var n: int = req["count"]
	var keys: Array = req["allowed"].duplicate()
	var key := {}
	for k in keys:
		key[k] = D.OBJECTIVES[k]["mult"] + rng.randf() * 1.5
	keys.sort_custom(func(a, b): return key[a] > key[b])
	return keys.slice(0, n)


func _setup_dist(e: GHEngine, s: int, req: Dictionary) -> Dictionary:
	var ids: Array = req["ids"]
	var ob: Array = req["objs"]
	var out := {}
	var strength := {}
	for k in ob:
		strength[k] = 0.0
	var vol := []
	var rest := []
	for id in ids:
		if e.cs[id]["t"] == "V":
			vol.append(id)
		else:
			rest.append(id)
	vol.sort_custom(func(a, b): return D.VOLUNTEERS[e.cs[a]["k"]][2] > D.VOLUNTEERS[e.cs[b]["k"]][2])
	for id in vol:
		var k0: String = ob[0]
		for k in ob:
			var b := 1 if e.cs[id]["k"] in D.OBJECTIVES[k]["vol"] else 0
			var b0 := 1 if e.cs[id]["k"] in D.OBJECTIVES[k0]["vol"] else 0
			if strength[k] - b * 3 < strength[k0] - b0 * 3:
				k0 = k
		out[id] = k0
		strength[k0] += D.VOLUNTEERS[e.cs[id]["k"]][2]
	var i := 0
	for id in rest:
		var k1: String = ob[0]
		for k in ob:
			if strength[k] < strength[k1]:
				k1 = k
		if e.cs[id]["t"] == "P":
			k1 = ob[i % ob.size()]
			i += 1
		out[id] = k1
		strength[k1] += 1.0
	return out


func _hmove(e: GHEngine, s: int, req: Dictionary) -> Dictionary:
	var mv: Dictionary = req["movable"]
	var thr := _threat(e)
	var best := {}
	var bv := 1.0
	for l in mv:
		var g: Dictionary = mv[l]
		var vols: Array = g["vol"]
		var items: Array = g["items"]
		var radio_ids := []
		for iid in items:
			if e.cs[iid]["t"] == "R":
				radio_ids.append(iid)
		if req["main_used"] and radio_ids.is_empty():
			continue
		var gstr := 0.0
		for id in vols:
			gstr += D.VOLUNTEERS[e.cs[id]["k"]][2]
		for to in g["to"]:
			var v := 0.0
			var take := vols.duplicate()
			if l.begins_with("t:") and to.begins_with("o:"):
				var k: String = to.substr(2)
				var own: int = e.objs[k]["owner"]
				var others := false
				for id in e.ids_at(to, "V"):
					if e.cs[id]["o"] != s:
						others = true
				var mine := own == s or (not others)
				var dfn := _defense(e, to)
				var need := maxf(0.0, thr[k] * 3.0 - dfn)
				if own == s:
					v = need * 1.0 + 2.0 + D.OBJECTIVES[k]["mult"]
				elif mine:
					v = 5.0 + D.OBJECTIVES[k]["mult"] * 2.0 - thr[k] * 0.5
				elif k == "cattedrale":
					v = need * 1.2 - 2.0
				else:
					v = need * 0.4 - 6.0
				for id in vols:
					if e.cs[id]["k"] in D.OBJECTIVES[k]["vol"]:
						v += 1.5
				if not e.ghouls_at(to).is_empty():
					var gs := e.ghouls_at(to).size() * AVG_GHOUL
					v += 5.0 if gstr + dfn > gs * 1.3 + 2 else -12.0
				v += vols.size() * 1.5
			elif l.begins_with("o:") and to.begins_with("c:"):
				# caccia ai ghoul nelle fogne, solo con un gruppo forte
				var gh := e.ghouls_at(to)
				var stay := _defense(e, l) - gstr
				if gh.is_empty() or level == 0:
					continue
				var est := gh.size() * AVG_GHOUL
				if gstr < est * 1.6 + 4 or stay < 3.0 + thr[l.substr(2)]:
					continue
				v = 6.0 + gh.size() * 2.0
			elif l.begins_with("c:"):
				# nelle fogne: verso il Covo se è sguarnito, altrimenti si torna su
				if to.begins_with("o:"):
					v = 4.0 + thr[to.substr(2)]
				else:
					var dc := _bfs(e, [e.covo_loc()])
					var gh2 := e.ghouls_at(to)
					var est2 := gh2.size() * AVG_GHOUL
					if gstr < est2 * 1.5 + 3:
						continue
					v = 3.0 + (float(dc.get(l, 9)) - float(dc.get(to, 9))) * 3.0
			elif l.begins_with("o:") and to.begins_with("t:"):
				continue
			v = _noise(v)
			if v > bv:
				bv = v
				var ids := take.duplicate()
				var carry := 0
				# prima le radio, poi mine verso gli obiettivi minacciati e punti verso i propri
				for iid in radio_ids:
					ids.append(iid)
				if to.begins_with("o:"):
					var k2: String = to.substr(2)
					var pts := []
					var mines := []
					for iid in items:
						if e.cs[iid]["t"] == "P":
							pts.append(iid)
						elif e.cs[iid]["t"] == "M":
							mines.append(iid)
					var order := []
					if thr[k2] > 0.8:
						order = mines + pts
					else:
						order = pts + mines
					for iid in order:
						if carry < take.size():
							ids.append(iid)
							carry += 1
				best = {"ids": ids, "to": to}
	return best


# ================================================================ combattimento

func _attacks(e: GHEngine, s: int, req: Dictionary) -> Array:
	var mode: String = req["mode"]
	var atk: Array = req["atk"]
	var tgt: Array = req["tgt"]
	var a_str := {}
	var t_str := {}
	var t_val := {}
	var a_cost := {}
	for id in atk:
		if mode == "gmelee":
			a_str[id] = float(e.gval(id))
			a_cost[id] = 1.0 + e.gval(id) * 0.4
		elif mode == "ranged":
			a_str[id] = float(e.hranged(id))
			a_cost[id] = 0.0
		else:
			a_str[id] = float(e.hmelee(id))
			a_cost[id] = 2.0 + e.hmelee(id) * 0.5
	for id in tgt:
		if mode == "gmelee":
			t_str[id] = float(e.hmelee(id))
			t_val[id] = 2.0 + e.hmelee(id) * 0.6
		else:
			var known: bool = e.revealed.has(id) or s == 0
			t_str[id] = float(e.gval(id)) if known else AVG_GHOUL
			t_val[id] = 1.0 + t_str[id] * 0.3
	# ogni bersaglio riceve un gruppo di attaccanti; si cerca l'assegnazione migliore con un
	# avido e qualche miglioramento locale
	var assign := {}
	var order := atk.duplicate()
	order.sort_custom(func(a, b): return a_str[a] > a_str[b])
	for id in order:
		var bt = null
		var bgain := -1e9
		for t in tgt:
			var before := _group_value(mode, assign, t, a_str, t_str, t_val, a_cost)
			assign[id] = t
			var after := _group_value(mode, assign, t, a_str, t_str, t_val, a_cost)
			assign.erase(id)
			var gain := after - before
			if gain > bgain:
				bgain = gain
				bt = t
		if mode == "ranged" and bgain <= 0.0:
			continue
		assign[id] = bt
	for it in (2 if level >= 1 else 0):
		for id in order:
			if not assign.has(id):
				continue
			var cur = assign[id]
			var base := _total(mode, assign, tgt, a_str, t_str, t_val, a_cost)
			for t in tgt:
				if t == cur:
					continue
				assign[id] = t
				var v := _total(mode, assign, tgt, a_str, t_str, t_val, a_cost)
				if v > base + 0.01:
					base = v
					cur = t
				assign[id] = cur
	var groups := {}
	for id in assign:
		var t = assign[id]
		if not groups.has(t):
			groups[t] = []
		groups[t].append(id)
	var out := []
	for t in groups:
		out.append([groups[t], [t]])
	return out


func _total(mode: String, assign: Dictionary, tgt: Array, a_str, t_str, t_val, a_cost) -> float:
	var v := 0.0
	for t in tgt:
		v += _group_value(mode, assign, t, a_str, t_str, t_val, a_cost)
	return v


func _group_value(mode: String, assign: Dictionary, t, a_str: Dictionary, t_str: Dictionary, t_val: Dictionary, a_cost: Dictionary) -> float:
	var sa := 0.0
	var cost := 0.0
	var n := 0
	for id in assign:
		if assign[id] == t:
			sa += a_str[id]
			cost += a_cost[id]
			n += 1
	if n == 0:
		return 0.0
	var p := p_attack(sa, t_str[t])
	match mode:
		"ranged":
			return p.x * t_val[t]
		"hmelee":
			return p.x * t_val[t] - p.z * cost - p.y * (cost + n * 1.5)
		"gmelee":
			return p.x * t_val[t] - p.z * cost + p.y * (t_val[t] + 1.0)
	return 0.0

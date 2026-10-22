extends Control
## Vista di gioco: le fogne a sinistra (MapView), gli Obiettivi della città e le tessere Trasporto a
## destra, la barra delle decisioni in basso, il pannello del combattimento, il diario e la fine partita.
## Informazioni nascoste: chi guida i Ghoul non vede le pedine coperte degli Obiettivi né dove portano i
## tombini che non ha ancora attraversato; gli Umani non vedono la forza dei ghoul finché non combattono.

const D = preload("res://scripts/data/gh_data.gd")

var main
var config: Dictionary
var engine: GHEngine
var online = null
var pending: Dictionary = {}
var viewer := -1
var omniscient := false
var local_seats: Array = []
var _dirty := false

var map                          # vista attiva: MapView (2D) o Board3D (3D)
var map2d: MapView
var map3d: Board3D
var view_btn: Button
var top_lbl: Label
var phase_lbl: Label
var status_lbl: Label
var dice_ctl: Control
var obj_cards: Dictionary = {}
var trans_rows: Dictionary = {}
var trans_box: VBoxContainer
var ticker: RichTextLabel
var dec_panel: PanelContainer
var dec_box: VBoxContainer
var combat_panel: PanelContainer
var combat_box: VBoxContainer
var log_panel: PanelContainer
var log_text: RichTextLabel
var curtain: Control
var side_btn: Button

# stato delle scelte in corso
var sel_src := ""
var sel_ids: Array = []
var sel_atk: Array = []
var att_groups: Dictionary = {}   # attaccante -> bersaglio
var objs_sel: Array = []
var dist: Dictionary = {}
var ghost_opt := -1
var last_ticker: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.reborn = str(config.get("style", "classico")) == "reborn"
	engine = GHEngine.new()
	add_child(engine)
	online = config.get("online", null)
	if online != null:
		add_child(online)
		online.view = self
		engine.online = online
	engine.setup(config)
	for s in engine.players.size():
		var p: Dictionary = engine.players[s]
		engine.ais[s] = GHAI.new(int(p["level"]), int(config.get("seed", 0)) * 7 + s + 1 if config.has("seed") else randi())
		if online != null:
			if s == online.seat:
				local_seats.append(s)
		elif not p["ai"]:
			local_seats.append(s)
	if local_seats.is_empty():
		omniscient = true
	else:
		viewer = local_seats[0]
	engine.ai_delay = float(config.get("ai_delay", 0.5))
	_build()
	engine.changed.connect(_mark)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.game_ended.connect(_on_end)
	engine.fx.connect(_on_fx)
	map2d.set_engine(engine)
	map3d.set_engine(engine)
	_refresh()
	map.fit.call_deferred()
	if online != null and online.role != "host":
		online.heartbeat_loop()
	engine.run.call_deferred()


func _mark() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


# ================================================================ prospettiva

func side() -> String:
	if omniscient:
		return "all"
	return "ghoul" if viewer == 0 else "umani"


func sees_ghoul(id: int) -> bool:
	return side() != "umani" or engine.revealed.has(id)


func sees_tomb(k: String) -> bool:
	return side() != "ghoul" or engine.ghoul_known.has(k)


func sees_obj() -> bool:
	return side() != "ghoul"


# ================================================================ costruzione

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	map2d = MapView.new()
	map2d.view = self
	map2d.position = Vector2(0, 64)
	map2d.size = Vector2(1180, 1016)
	add_child(map2d)
	map3d = Board3D.new()
	map3d.view = self
	map3d.position = Vector2(0, 64)
	map3d.size = Vector2(1180, 1016)
	add_child(map3d)
	for m in [map2d, map3d]:
		m.loc_clicked.connect(_on_loc_click)
		m.tomb_clicked.connect(_on_tomb_click)
	var v3: bool = config.get("view3d", false)
	map = map3d if v3 else map2d
	map2d.visible = not v3
	map3d.visible = v3
	# barra in alto
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.panel_style(Color(0.05, 0.06, 0.04, 0.97), Color(UI.SLIME_D, 0.6), 0, 0))
	top.position = Vector2.ZERO
	top.size = Vector2(1920, 62)
	top.custom_minimum_size = Vector2(1920, 62)
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top.add_child(th)
	th.add_child(UI.title("GHOULS", 38))
	top_lbl = UI.label("", 22, UI.ACID_L, UI.font_bold)
	th.add_child(top_lbl)
	dice_ctl = DiceBox.new()
	dice_ctl.view = self
	dice_ctl.custom_minimum_size = Vector2(130, 44)
	th.add_child(dice_ctl)
	phase_lbl = UI.label("", 19, UI.TEXT)
	phase_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_lbl.clip_text = true
	th.add_child(phase_lbl)
	status_lbl = UI.label("", 17, UI.MUTED)
	th.add_child(status_lbl)
	if omniscient:
		side_btn = UI.button("Vista: tutto", 150, 42, 17)
		side_btn.pressed.connect(_cycle_side)
		th.add_child(side_btn)
	view_btn = UI.button("Vista 2D" if map == map3d else "Vista 3D", 120, 42, 17)
	view_btn.pressed.connect(_toggle_3d)
	th.add_child(view_btn)
	for spec in [["Centra", func(): map.fit()], ["Diario", _toggle_log], ["Regole", _show_rules_popup], ["Menu", _confirm_menu]]:
		var b := UI.button(spec[0], 104, 42, 17)
		b.pressed.connect(spec[1])
		th.add_child(b)
	# colonna destra: Obiettivi e Trasporti
	var rc := VBoxContainer.new()
	rc.position = Vector2(1188, 68)
	rc.custom_minimum_size = Vector2(726, 0)
	rc.add_theme_constant_override("separation", 6)
	add_child(rc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	rc.add_child(grid)
	for k in D.OBJ_ORDER:
		var c := ObjCard.new()
		c.view = self
		c.key = k
		c.custom_minimum_size = Vector2(360, 104)
		grid.add_child(c)
		obj_cards[k] = c
	trans_box = VBoxContainer.new()
	trans_box.add_theme_constant_override("separation", 6)
	rc.add_child(trans_box)
	for s in range(1, engine.players.size()):
		var tr := TransRow.new()
		tr.view = self
		tr.seat = s
		tr.custom_minimum_size = Vector2(726, 78)
		trans_box.add_child(tr)
		trans_rows[s] = tr
	ticker = RichTextLabel.new()
	ticker.bbcode_enabled = true
	ticker.scroll_following = true
	ticker.custom_minimum_size = Vector2(726, 150)
	ticker.add_theme_font_size_override("normal_font_size", 16)
	ticker.add_theme_font_size_override("bold_font_size", 16)
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc.add_child(ticker)
	# barra delle decisioni (sopra la mappa, in basso)
	dec_panel = PanelContainer.new()
	dec_panel.add_theme_stylebox_override("panel", UI.dark_style(10, 0.96))
	dec_panel.position = Vector2(10, 900)
	dec_panel.custom_minimum_size = Vector2(1160, 0)
	dec_panel.visible = false
	add_child(dec_panel)
	dec_box = VBoxContainer.new()
	dec_box.add_theme_constant_override("separation", 8)
	dec_panel.add_child(dec_box)
	dec_panel.resized.connect(_place_dec)
	# combattimento
	combat_panel = PanelContainer.new()
	combat_panel.add_theme_stylebox_override("panel", UI.dark_style(12, 0.97))
	combat_panel.position = Vector2(70, 110)
	combat_panel.custom_minimum_size = Vector2(1040, 0)
	combat_panel.visible = false
	add_child(combat_panel)
	combat_box = VBoxContainer.new()
	combat_box.add_theme_constant_override("separation", 10)
	combat_panel.add_child(combat_box)
	# diario
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", UI.dark_style(10, 0.97))
	log_panel.position = Vector2(1188, 68)
	log_panel.size = Vector2(726, 1000)
	log_panel.custom_minimum_size = Vector2(726, 1000)
	log_panel.visible = false
	add_child(log_panel)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.add_theme_font_size_override("normal_font_size", 18)
	log_panel.add_child(log_text)


func _toggle_3d() -> void:
	var to3: bool = map == map2d
	map = map3d if to3 else map2d
	map2d.visible = not to3
	map3d.visible = to3
	view_btn.text = "Vista 2D" if to3 else "Vista 3D"
	map.focus = map2d.focus if to3 else map3d.focus
	_refresh()
	map.ensure_visible()


func _place_dec() -> void:
	dec_panel.position = Vector2(10, 1072 - dec_panel.size.y)


func _cycle_side() -> void:
	if viewer == -1:
		viewer = 1
		omniscient = false
		side_btn.text = "Vista: Umani"
	elif viewer >= 1:
		viewer = 0
		side_btn.text = "Vista: Ghoul"
	else:
		viewer = -1
		omniscient = true
		side_btn.text = "Vista: tutto"
	_refresh()


# ================================================================ aggiornamento

func _refresh() -> void:
	_dirty = false
	var e := engine
	var dawn := "" if e.max_turns <= 0 else " / alba al %d" % e.max_turns
	top_lbl.text = "Turno %d%s" % [maxi(1, e.turn_no), dawn]
	var ph := ""
	match e.phase:
		"setup":
			ph = "Preparazione"
		"inizio":
			ph = "Inizio del turno"
		"ghoul":
			ph = "I Ghoul si muovono (%d movimenti)" % e.gmove_left
		"numeri":
			ph = "Gli Umani scelgono i segnalini numerati"
		"umano", "umano_fine":
			ph = "Muove %s" % e.pname(e.active_human) if e.active_human >= 1 else "Umani"
		"combattimento":
			ph = "Combattimenti"
		"fine":
			ph = "Fine del turno"
		"fine_partita":
			ph = "Partita finita"
	if e.covo_streak > 0:
		ph += "  ·  Covo occupato %d/%d" % [e.covo_streak, GHEngine.COVO_TURNS]
	phase_lbl.text = ph + "  ·  mazzo fogne: %d  ·  ghoul nel contenitore: %d" % [e.tile_deck.size(), e.gpool.size()]
	dice_ctl.queue_redraw()
	for k in obj_cards:
		obj_cards[k].queue_redraw()
		obj_cards[k].tooltip_text = obj_tooltip(k)
	for s in trans_rows:
		trans_rows[s].queue_redraw()
		trans_rows[s].tooltip_text = trans_tooltip(s)
	_update_highlights()
	map.ensure_visible()
	map.redraw()
	_refresh_combat()


func _update_highlights() -> void:
	map.allowed = {}
	map.allowed_tombs = {}
	map.source = sel_src
	map.ghost = []
	for k in obj_cards:
		obj_cards[k].hl = ""
	for s in trans_rows:
		trans_rows[s].hl = ""
	if pending.is_empty():
		return
	var req := pending
	match req["type"]:
		"gmove":
			var mv: Dictionary = req["movable"]
			for l in mv:
				_mark_loc(l, "src")
			if sel_src != "":
				for to in engine.ghoul_moves_from(sel_src):
					if to.begins_with("o:"):
						var k: String = to.substr(2)
						map.allowed_tombs["%s|%s" % [sel_src, k]] = true
						if sees_tomb(k) or sel_src.begins_with("o:"):
							_mark_loc(to, "dst")
					else:
						_mark_loc(to, "dst")
		"hmove":
			var mv2: Dictionary = req["movable"]
			for l in mv2:
				_mark_loc(l, "src")
			if sel_src != "" and mv2.has(sel_src):
				for to in mv2[sel_src]["to"]:
					if to.begins_with("o:") and sel_src.begins_with("c:"):
						map.allowed_tombs["%s|%s" % [sel_src, to.substr(2)]] = true
					_mark_loc(to, "dst")
		"tile":
			for o in req["options"]:
				map.allowed["c:%d,%d" % [o[0], o[1]]] = true
			if ghost_opt >= 0 and ghost_opt < (req["options"] as Array).size():
				var o2: Array = req["options"][ghost_opt]
				map.ghost = [req["kind"], o2[0], o2[1], o2[2]]
		"loc":
			for l in req["allowed"]:
				_mark_loc(l, "dst")
		"objs":
			for k in req["allowed"]:
				obj_cards[k].hl = "sel" if objs_sel.has(k) else "dst"


func _mark_loc(l: String, kind: String) -> void:
	if l.begins_with("o:"):
		var k := l.substr(2)
		if obj_cards.has(k):
			obj_cards[k].hl = "src" if l == sel_src else kind
	elif l.begins_with("t:"):
		var s := int(l.substr(2))
		if trans_rows.has(s):
			trans_rows[s].hl = "src" if l == sel_src else kind
	elif l.begins_with("c:"):
		if kind == "dst" or sel_src == "":
			map.allowed[l] = true


# ================================================================ testi d'aiuto

func tile_tooltip(loc: String) -> String:
	var key := loc.substr(2)
	if not engine.tiles.has(key):
		return ""
	var t: Dictionary = engine.tiles[key]
	var lines := [D.TILES[t["k"]]["name"]]
	for k in t["tomb"]:
		if k == "":
			lines.append("Tombino senza Locazione (finite): non porta da nessuna parte")
		elif sees_tomb(k):
			lines.append("Tombino → %s%s" % [D.obj_name(k), " (devastato)" if engine.objs[k]["dev"] else ""])
		else:
			lines.append("Tombino → ? (lo scoprirai attraversandolo)")
	var gh := engine.ghouls_at(loc)
	if not gh.is_empty():
		var vv := []
		for id in gh:
			vv.append(str(engine.gval(id)) if sees_ghoul(id) and engine.cs[id]["t"] == "G" else ("S" if sees_ghoul(id) else "?"))
		lines.append("Ghoul: %d  [%s]" % [gh.size(), " ".join(vv)])
	for id in engine.ids_at(loc, "VFR"):
		lines.append("%s · %s" % [_cdesc(id), engine.pname(engine.cs[id]["o"])])
	return "\n".join(lines)


func _cdesc(id: int) -> String:
	var c: Dictionary = engine.cs[id]
	if c["t"] == "V":
		var r := engine.hranged(id)
		return "%s (distanza %s, corpo a corpo %d)" % [engine.cname(id), "—" if r < 0 else str(r), engine.hmelee(id)]
	return engine.cname(id)


func obj_tooltip(k: String) -> String:
	var o: Dictionary = D.OBJECTIVES[k]
	var vols := []
	for v in o["vol"]:
		vols.append(D.vol_name(v))
	var lines := ["%s — moltiplicatore ×%d" % [o["name"], o["mult"]], "+1 in combattimento: " + ", ".join(vols)]
	var ow: int = engine.objs[k]["owner"]
	lines.append("Controllato da: %s" % (engine.pname(ow) if ow >= 1 else "nessuno"))
	if engine.objs[k]["dev"]:
		lines.append("DEVASTATO: i volontari %s pescati da ora escono dal gioco" % ", ".join(vols))
	elif o["dev"] > 0:
		lines.append("Se devastato arrivano %d ghoul" % o["dev"])
	var l := "o:" + k
	if sees_obj():
		for id in engine.ids_at(l, "VFPMR"):
			lines.append("· " + _cdesc(id))
		lines.append("Valore: %d punti" % engine.obj_value(k))
	else:
		lines.append("Pedine coperte: %d" % engine.ids_at(l, "VFPMR").size())
	if side() == "ghoul":
		lines.append("Il tombino per arrivarci: %s" % ("conosciuto" if engine.ghoul_known.has(k) else "sconosciuto"))
	return "\n".join(lines)


func trans_tooltip(s: int) -> String:
	var lines := ["Tessera Trasporto di %s (pedine scoperte, non può essere attaccata)" % engine.pname(s)]
	var used: Array = engine.tokens_used[s]
	var av := []
	for v in range(1, 6):
		if not used.has(v):
			av.append(str(v))
	lines.append("Segnalini numerati ancora disponibili: " + ", ".join(av))
	lines.append("Ghoul eliminati: %d" % engine.kills[s])
	for id in engine.ids_at("t:%d" % s):
		lines.append("· " + _cdesc(id))
	return "\n".join(lines)


# ================================================================ decisioni

func _on_decision(req: Dictionary) -> void:
	pending = req
	sel_src = ""
	sel_ids = []
	sel_atk = []
	att_groups = {}
	objs_sel = []
	dist = {}
	ghost_opt = -1
	var s: int = req["seat"]
	if s in local_seats:
		var switch := s != viewer and local_seats.size() > 1
		# nel combattimento le pedine sono scoperte: si cambia prospettiva senza tendina
		var hidden: bool = ((s == 0) != (viewer == 0) and req["type"] != "attacks") or req["type"] == "token"
		if switch and hidden:
			viewer = s
			_show_curtain(s)
		else:
			viewer = s
	match req["type"]:
		"dist":
			var sug = GHAI.new(1, 1).decide(engine, s, req)
			if sug is Dictionary:
				dist = sug.duplicate()
		"tile":
			if req["ctx"] == "explore" or (req["options"] as Array).size() == 1:
				ghost_opt = 0
		"gmove":
			var mv: Dictionary = req["movable"]
			if mv.size() == 1:
				_select_src(mv.keys()[0])
		"hmove":
			var mv2: Dictionary = req["movable"]
			if mv2.size() == 1:
				_select_src(mv2.keys()[0])
	_show_decision()
	_refresh()


func _select_src(l: String) -> void:
	sel_src = l
	sel_ids = []
	if pending["type"] == "gmove":
		var ids: Array = pending["movable"][l].duplicate()
		ids.sort_custom(func(a, b): return engine.gval(a) > engine.gval(b))
		sel_ids = ids.slice(0, int(pending["left"]))
	elif pending["type"] == "hmove":
		var g: Dictionary = pending["movable"][l]
		sel_ids = (g["vol"] as Array).duplicate()
		var cap: int = sel_ids.size()
		for iid in g["items"]:
			if engine.cs[iid]["t"] == "R":
				sel_ids.append(iid)
			elif l.begins_with("t:") and cap > 0:
				sel_ids.append(iid)
				cap -= 1


func _show_decision() -> void:
	for c in dec_box.get_children():
		dec_box.remove_child(c)
		c.queue_free()
	if pending.is_empty():
		dec_panel.visible = false
		return
	var req := pending
	if req["type"] == "attacks":
		dec_panel.visible = false
		_refresh_combat()
		return
	dec_panel.visible = true
	var s: int = req["seat"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var sw := ColorRect.new()
	sw.color = UI.seat_col(engine, s)
	sw.custom_minimum_size = Vector2(10, 34)
	head.add_child(sw)
	var tl := UI.label("%s — %s" % [engine.pname(s), str(req.get("title", ""))], 22, UI.ACID_L, UI.font_bold)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = 1100
	head.add_child(tl)
	dec_box.add_child(head)
	match req["type"]:
		"pick":
			var row := HBoxContainer.new()
			for i in (req["options"] as Array).size():
				var b := UI.button(str(req["options"][i]), 220, 46)
				var ii := i
				b.pressed.connect(func(): _provide(ii))
				row.add_child(b)
			dec_box.add_child(row)
		"token":
			_show_token(req)
		"loc":
			_show_loc(req)
		"tile":
			_show_tile(req)
		"gmove":
			_show_gmove(req)
		"hmove":
			_show_hmove(req)
		"objs":
			_show_objs(req)
		"dist":
			_show_dist(req)
	dec_panel.size = Vector2(1160, 0)
	dec_panel.reset_size()
	_place_dec.call_deferred()


func _hint(t: String) -> void:
	dec_box.add_child(UI.wrap(UI.label(t, 18, UI.MUTED), 1120))


func _show_token(req: Dictionary) -> void:
	var s: int = req["seat"]
	_hint("Tutti scelgono in segreto, poi i numeri si rivelano insieme. Il più alto resta fermo, i numeri uguali saltano il turno; chi ha il più basso muove per primo e piazza la tessera fogna. Con il numero scelto peschi altrettante pedine Umani.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for v in range(1, 6):
		var b := Button.new()
		b.text = str(v)
		b.custom_minimum_size = Vector2(84, 84)
		b.add_theme_font_override("font", UI.font_title)
		b.add_theme_font_size_override("font_size", 46)
		var col := UI.seat_col(engine, s)
		b.add_theme_stylebox_override("normal", UI.panel_style(col.darkened(0.15), Color.BLACK, 3, 8))
		b.add_theme_stylebox_override("hover", UI.panel_style(col.lightened(0.15), Color.WHITE, 3, 8))
		b.add_theme_color_override("font_color", Color.BLACK)
		b.add_theme_color_override("font_hover_color", Color.BLACK)
		b.disabled = not (v in req["options"])
		var vv := v
		b.pressed.connect(func(): _provide(vv))
		row.add_child(b)
	dec_box.add_child(row)


func _show_loc(req: Dictionary) -> void:
	match req["ctx"]:
		"folla":
			_hint("La Folla va direttamente su un Obiettivo (non devastato). Da sola non ne dà il controllo. Clicca un Obiettivo evidenziato.")
		"combat_order":
			_hint("Scegli quale combattimento risolvere per primo (tessere o Obiettivi evidenziati).")
		"covo_kill":
			_hint("Hai volontari nel Covo: puoi togliere dal gioco una pedina ghoul (a caso fra quelle della locazione scelta) e guadagnare 1 punto.")
		"setup_pick":
			_hint("Scegli quale degli Obiettivi preparati difenderai.")
		_:
			_hint("Clicca una delle locazioni evidenziate.")
	if req.get("skip", false):
		var b := UI.button("Rinuncia", 200, 44)
		b.pressed.connect(func(): _provide(""))
		dec_box.add_child(b)


func _show_tile(req: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var preview := UI.icon_rect(UI.tile_tex(req["kind"]), Vector2(90, 90))
	row.add_child(preview)
	var vb := VBoxContainer.new()
	vb.add_child(UI.label(D.TILES[req["kind"]]["name"], 21, Color.WHITE, UI.font_bold))
	if req["ctx"] == "explore":
		vb.add_child(UI.wrap(UI.label("I ghoul escono dalla mappa: la nuova tessera va girata in modo che i corridoi comunichino. Ruota per scegliere fra i modi possibili.", 18, UI.MUTED), 760))
	else:
		vb.add_child(UI.wrap(UI.label("Chi ha giocato il numero più basso piazza la tessera: clicca una casella evidenziata, clicca di nuovo (o Ruota) per girarla. Puoi usarla per chiudere le gallerie ai ghoul!", 18, UI.MUTED), 760))
	row.add_child(vb)
	var rot := UI.button("Ruota", 130, 50)
	rot.pressed.connect(func(): _rotate_ghost())
	row.add_child(rot)
	var ok := UI.primary(UI.button("Conferma", 170, 50))
	ok.disabled = ghost_opt < 0
	ok.pressed.connect(func():
		if ghost_opt >= 0:
			_provide(ghost_opt))
	row.add_child(ok)
	dec_box.add_child(row)


func _rotate_ghost() -> void:
	var opts: Array = pending["options"]
	if ghost_opt < 0:
		ghost_opt = 0
	else:
		var cur: Array = opts[ghost_opt]
		for j in range(1, opts.size() + 1):
			var o: Array = opts[(ghost_opt + j) % opts.size()]
			if o[0] == cur[0] and o[1] == cur[1]:
				ghost_opt = (ghost_opt + j) % opts.size()
				break
	_show_decision()
	_refresh()


func _counter_button(id: int, on: bool, face: bool, cb: Callable, sz := 62.0) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(sz, sz)
	b.icon = UI.counter_tex(engine.cs[id]) if face else UI.ghoul_back()
	b.expand_icon = true
	b.add_theme_stylebox_override("normal", UI.panel_style(Color(0, 0, 0, 0.3), UI.ACID if on else Color("#333"), 3 if on else 1, 4))
	b.add_theme_stylebox_override("hover", UI.panel_style(Color(1, 1, 1, 0.1), UI.ACID_L, 3, 4))
	b.add_theme_constant_override("icon_max_width", int(sz - 8))
	b.modulate = Color.WHITE if on else Color(0.55, 0.55, 0.55)
	b.tooltip_text = _cdesc(id) if face else "Ghoul coperto"
	b.pressed.connect(cb)
	return b


func _show_gmove(req: Dictionary) -> void:
	var left: int = req["left"]
	if sel_src == "":
		_hint("Clicca una pila di ghoul evidenziata (sulle fogne o in un Obiettivo devastato). Ogni pedina si muove di una tessera; i ghoul che escono dalla mappa fanno pescare una nuova tessera; da un tombino si sale nell'Obiettivo collegato.")
	else:
		_hint("Da %s: scegli le pedine (%d al massimo) e clicca la destinazione evidenziata. Per salire in un Obiettivo clicca il tombino sulla tessera." % [engine.loc_name(sel_src), left])
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		for id in req["movable"][sel_src]:
			var iid: int = id
			row.add_child(_counter_button(iid, sel_ids.has(iid), true, func():
				if sel_ids.has(iid):
					sel_ids.erase(iid)
				elif sel_ids.size() < left:
					sel_ids.append(iid)
				_show_decision()))
		dec_box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	var end := UI.button("Fine movimento", 230, 46)
	end.pressed.connect(func(): _provide({}))
	row2.add_child(end)
	dec_box.add_child(row2)


func _show_hmove(req: Dictionary) -> void:
	var s: int = req["seat"]
	if sel_src == "":
		if req["main_used"]:
			_hint("Puoi ancora muovere i gruppi muniti di Radio (la Radio va portata con il gruppo).")
		else:
			_hint("Puoi muovere UN gruppo di volontari da una sola locazione (più i gruppi con la Radio): dal Trasporto a qualunque Obiettivo, da un Obiettivo al tuo Trasporto o giù nelle fogne dal suo tombino, nelle fogne di una tessera alla volta. Clicca la locazione di partenza.")
	else:
		var g: Dictionary = req["movable"][sel_src]
		_hint("Da %s: scegli chi parte (ogni volontario porta con sé una Mina o un Punto Vittoria; le Radio viaggiano libere) e clicca la destinazione." % engine.loc_name(sel_src))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		for id in (g["vol"] as Array) + (g["items"] as Array):
			var iid: int = id
			row.add_child(_counter_button(iid, sel_ids.has(iid), true, func():
				if sel_ids.has(iid):
					sel_ids.erase(iid)
				else:
					sel_ids.append(iid)
				_show_decision()))
		dec_box.add_child(row)
		var nv := 0
		var ni := 0
		var radio := false
		for id in sel_ids:
			var t: String = engine.cs[id]["t"]
			if t == "V":
				nv += 1
			elif t == "R":
				radio = true
			else:
				ni += 1
		if ni > nv:
			dec_box.add_child(UI.label("Troppe Mine e Punti Vittoria: ne partiranno solo %d." % nv, 18, UI.BLOOD_L))
		if req["main_used"] and not radio:
			dec_box.add_child(UI.label("Serve una Radio nel gruppo per questo movimento.", 18, UI.BLOOD_L))
	var row2 := HBoxContainer.new()
	var end := UI.button("Fine movimento", 230, 46)
	end.pressed.connect(func(): _provide({}))
	row2.add_child(end)
	dec_box.add_child(row2)


func _show_objs(req: Dictionary) -> void:
	_hint("Clicca %d Obiettivi della città: le pedine pescate verranno distribuite su questi, poi ogni giocatore sceglierà quale difendere." % req["count"])
	var ok := UI.primary(UI.button("Conferma (%d/%d)" % [objs_sel.size(), req["count"]], 260, 48))
	ok.disabled = objs_sel.size() != int(req["count"])
	ok.pressed.connect(func(): _provide(objs_sel.duplicate()))
	var row := HBoxContainer.new()
	row.add_child(ok)
	dec_box.add_child(row)


func _show_dist(req: Dictionary) -> void:
	_hint("Decidi su quale Obiettivo va ogni pedina pescata (proposta automatica già pronta).")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	for id in req["ids"]:
		var iid: int = id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.icon_rect(UI.counter_tex(engine.cs[iid]), Vector2(44, 44)))
		var nl := UI.label(engine.cname(iid), 16)
		nl.custom_minimum_size.x = 128
		row.add_child(nl)
		for k in req["objs"]:
			var kk: String = k
			var b := UI.button(D.obj_name(kk).substr(0, 11), 108, 38, 14)
			var on: bool = dist.get(iid, "") == kk
			if on:
				b.add_theme_stylebox_override("normal", UI.panel_style(UI.SLIME, UI.SLIME, 2, 4))
				b.add_theme_color_override("font_color", UI.INK)
			b.pressed.connect(func():
				dist[iid] = kk
				_show_decision())
			row.add_child(b)
		grid.add_child(row)
	dec_box.add_child(grid)
	var ok := UI.primary(UI.button("Conferma", 220, 48))
	ok.pressed.connect(func(): _provide(dist.duplicate()))
	var row2 := HBoxContainer.new()
	row2.add_child(ok)
	dec_box.add_child(row2)


# ---------------------------------------------------------------- clic

func _on_loc_click(l: String) -> void:
	if pending.is_empty():
		return
	var req := pending
	match req["type"]:
		"gmove":
			var mv: Dictionary = req["movable"]
			if sel_src != "" and l in engine.ghoul_moves_from(sel_src) and not sel_ids.is_empty():
				_provide({"ids": sel_ids.duplicate(), "to": l})
			elif mv.has(l):
				_select_src(l)
				_show_decision()
				_refresh()
		"hmove":
			var mv2: Dictionary = req["movable"]
			if sel_src != "" and mv2.has(sel_src) and l in mv2[sel_src]["to"]:
				var has_vol := false
				for id in sel_ids:
					if engine.cs[id]["t"] == "V":
						has_vol = true
				if has_vol:
					_provide({"ids": sel_ids.duplicate(), "to": l})
			elif mv2.has(l):
				_select_src(l)
				_show_decision()
				_refresh()
		"tile":
			var opts: Array = req["options"]
			var p := GHEngine.cell(l) if l.begins_with("c:") else Vector2i(-999, -999)
			if ghost_opt >= 0 and opts[ghost_opt][0] == p.x and opts[ghost_opt][1] == p.y:
				_rotate_ghost()
				return
			for i in opts.size():
				if opts[i][0] == p.x and opts[i][1] == p.y:
					ghost_opt = i
					_show_decision()
					_refresh()
					return
		"loc":
			if l in req["allowed"]:
				_provide(l)
		"objs":
			if l.begins_with("o:"):
				var k := l.substr(2)
				if objs_sel.has(k):
					objs_sel.erase(k)
				elif objs_sel.size() < int(req["count"]):
					objs_sel.append(k)
				_show_decision()
				_refresh()


func _on_tomb_click(tile: String, k: String) -> void:
	if pending.is_empty():
		_on_loc_click(tile)
		return
	if (pending["type"] == "gmove" or pending["type"] == "hmove") and sel_src == tile:
		if map.allowed_tombs.has("%s|%s" % [tile, k]):
			_on_loc_click("o:" + k)
			return
	_on_loc_click(tile)


func _provide(v) -> void:
	if pending.is_empty():
		return
	pending = {}
	sel_src = ""
	sel_ids = []
	sel_atk = []
	att_groups = {}
	ghost_opt = -1
	dec_panel.visible = false
	engine.provide_decision(v)
	_mark()


# ================================================================ combattimento

func _refresh_combat() -> void:
	var c: Dictionary = engine.combat
	var att: bool = not pending.is_empty() and pending["type"] == "attacks"
	if c.is_empty() and not att:
		combat_panel.visible = false
		map2d.focus = ""
		map3d.focus = ""
		return
	combat_panel.visible = true
	for ch in combat_box.get_children():
		combat_box.remove_child(ch)
		ch.queue_free()
	var loc: String = c.get("loc", pending.get("loc", ""))
	if loc == "":
		combat_panel.visible = false
		return
	map2d.focus = loc
	map3d.focus = loc
	var step: String = c.get("step", "")
	var step_t: String = {"ranged": "Tiro da lontano", "hmelee": "Corpo a corpo: attaccano gli Umani", "gmelee": "Corpo a corpo: attaccano i Ghoul"}.get(step, "")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.add_child(UI.title("Combattimento", 40, UI.BLOOD_L))
	var sub := UI.label("%s%s%s" % [engine.loc_name(loc), ("  ·  " + step_t) if step_t != "" else "", "  ·  round %d" % c.get("round", 0) if int(c.get("round", 0)) > 0 else ""], 22, UI.BONE, UI.font_semi)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	if c.get("surprise", false):
		head.add_child(UI.label("SORPRESA!", 24, UI.ACID, UI.font_bold))
	combat_box.add_child(head)
	var mode: String = pending.get("mode", "") if att else ""
	var atk: Array = pending.get("atk", []) if att else []
	var tgt: Array = pending.get("tgt", []) if att else []
	var mine: bool = att and int(pending["seat"]) in local_seats
	# gruppi: numero per bersaglio
	var gnum := {}
	for a in att_groups:
		var t = att_groups[a]
		if not gnum.has(t):
			gnum[t] = gnum.size() + 1
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	combat_box.add_child(cols)
	for side_i in 2:
		var vb := VBoxContainer.new()
		vb.custom_minimum_size.x = 490
		var ghoul_side := side_i == 1
		vb.add_child(UI.heading("I Ghoul" if ghoul_side else "Gli Umani", 24, UI.GHOUL_C if ghoul_side else UI.ACID))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		vb.add_child(flow)
		var ids := engine.ghouls_at(loc) if ghoul_side else engine.humans_at(loc)
		for id in ids:
			var iid: int = id
			var face := sees_ghoul(iid) if ghoul_side else true
			var is_atk := atk.has(iid)
			var is_tgt := tgt.has(iid)
			var badge := 0
			if att_groups.has(iid):
				badge = gnum[att_groups[iid]]
			elif gnum.has(iid):
				badge = gnum[iid]
			var cc := CombatCounter.new()
			cc.view = self
			cc.id = iid
			cc.face = face
			cc.badge = badge
			cc.selected = sel_atk.has(iid)
			cc.clickable = mine and (is_atk or is_tgt)
			cc.dim = att and not is_atk and not is_tgt
			cc.custom_minimum_size = Vector2(92, 128)
			cc.tooltip_text = (_cdesc(iid) + " · " + engine.pname(engine.cs[iid]["o"])) if not ghoul_side else ("Ghoul da %d" % engine.gval(iid) if face and engine.cs[iid]["t"] == "G" else "Ghoul coperto")
			cc.pressed.connect(func(): _combat_click(iid))
			flow.add_child(cc)
		cols.add_child(vb)
	# ultimo attacco
	var last: Array = c.get("last", [])
	if not last.is_empty():
		var lr := LastAttack.new()
		lr.data = last[0]
		lr.custom_minimum_size = Vector2(1000, 64)
		combat_box.add_child(lr)
	if att:
		if mine:
			var hint: String = {"ranged": "Clicca uno o più tiratori, poi il ghoul da colpire. Si somma il valore a distanza + un dado contro la forza dei ghoul + un dado: se vinci, i ghoul sono eliminati. Chi non spara resta fermo.",
				"hmelee": "Clicca uno o più umani, poi il ghoul da attaccare: tutti devono attaccare (chi resta senza bersaglio viene assegnato da solo). Vinci: ghoul eliminati. Perdi: umani fatti a pezzi. Parità: gli umani diventano ghoul!",
				"gmelee": "Clicca uno o più ghoul, poi l'umano da attaccare: tutti i ghoul attaccano. Vinci: umani eliminati (in parità diventano ghoul). Perdi: i ghoul tornano nel contenitore."}[mode]
			combat_box.add_child(UI.wrap(UI.label(hint, 18, UI.MUTED), 1000))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var sug := UI.button("Suggerisci", 180, 48)
			sug.pressed.connect(func():
				var r = GHAI.new(2, randi()).decide(engine, pending["seat"], pending)
				att_groups = {}
				for g in r:
					for a in g[0]:
						att_groups[a] = g[1][0]
				sel_atk = []
				_refresh_combat())
			row.add_child(sug)
			var clr := UI.button("Azzera", 140, 48)
			clr.pressed.connect(func():
				att_groups = {}
				sel_atk = []
				_refresh_combat())
			row.add_child(clr)
			var go := UI.primary(UI.button("Attacca!" if mode != "ranged" else "Spara!", 220, 48))
			go.pressed.connect(_confirm_attacks)
			row.add_child(go)
			combat_box.add_child(row)
		else:
			combat_box.add_child(UI.label("%s assegna gli attacchi…" % engine.pname(pending["seat"]), 20, UI.MUTED))
	combat_panel.reset_size()


func _combat_click(id: int) -> void:
	if pending.is_empty() or pending["type"] != "attacks":
		return
	var atk: Array = pending["atk"]
	var tgt: Array = pending["tgt"]
	if atk.has(id):
		if att_groups.has(id):
			att_groups.erase(id)
		if sel_atk.has(id):
			sel_atk.erase(id)
		else:
			sel_atk.append(id)
	elif tgt.has(id) and not sel_atk.is_empty():
		for a in sel_atk:
			att_groups[a] = id
		sel_atk = []
	_refresh_combat()


func _confirm_attacks() -> void:
	var groups := {}
	for a in att_groups:
		var t = att_groups[a]
		if not groups.has(t):
			groups[t] = []
		groups[t].append(a)
	var out := []
	for t in groups:
		out.append([groups[t], [t]])
	_provide(out)


# ================================================================ varie

func _on_log(t: String) -> void:
	var col := "#e9e4d4"
	if t.begins_with("═"):
		col = "#ffd166"
	elif t.begins_with("—"):
		col = "#c8e27a"
	elif t.contains("DEVASTATO") or t.contains("fatti a pezzi") or t.contains("diventano ghoul"):
		col = "#ff7a66"
	elif t.contains("eliminat") or t.contains("BOOM"):
		col = "#9fe08a"
	elif t.begins_with("■"):
		col = "#f5a623"
	var line := "[color=%s]%s[/color]" % [col, t]
	log_text.append_text(line + "\n")
	last_ticker.append(line)
	if last_ticker.size() > 7:
		last_ticker.pop_front()
	ticker.clear()
	ticker.append_text("\n".join(last_ticker))


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"tile":
			map.ensure_visible()
		"combat":
			map2d.focus = data["loc"]
			map3d.focus = data["loc"]
		"devastated":
			status_lbl.text = "%s è stato devastato!" % D.obj_name(data["obj"])


func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible


func _show_curtain(s: int) -> void:
	if is_instance_valid(curtain):
		curtain.queue_free()
	curtain = ColorRect.new()
	(curtain as ColorRect).color = Color(0.02, 0.03, 0.02, 1.0)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(curtain)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	cc.add_child(vb)
	vb.add_child(UI.icon_rect(UI.tex("res://assets/counters/g5.png") if s == 0 else UI.tex("res://assets/misc/trasporto.jpg"), Vector2(260, 200)))
	var t := UI.title("Tocca a %s" % engine.pname(s), 54, UI.seat_col(engine, s))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := UI.label("Passa il dispositivo: gli altri non guardino!", 22, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var b := UI.primary(UI.button("Sono pronto", 300, 60, 24))
	b.pressed.connect(func(): curtain.queue_free())
	vb.add_child(b)


func _confirm_menu() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Abbandonare la partita e tornare al menu?"
	dlg.ok_button_text = "Sì"
	dlg.cancel_button_text = "No"
	add_child(dlg)
	dlg.confirmed.connect(func():
		engine.abort = true
		if online != null:
			online.alive = false
		main.show_menu())
	dlg.popup_centered()


func _show_rules_popup() -> void:
	var p := preload("res://scripts/ui/rules_view.gd").new()
	p.overlay = true
	add_child(p)


func _on_end(results: Array) -> void:
	pending = {}
	dec_panel.visible = false
	combat_panel.visible = false
	if online != null:
		online.finish()
	if engine.abort:
		return
	omniscient = true
	_refresh()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.dark_style(12, 0.98))
	pc.position = Vector2(500, 170)
	pc.custom_minimum_size = Vector2(920, 0)
	shade.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var gw := engine.winner == "ghoul"
	var t := UI.title("I Ghouls hanno vinto!" if gw else "La città è salva!", 64, UI.BLOOD_L if gw else UI.SLIME)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var r0 := UI.label(engine.end_reason, 22, UI.BONE)
	r0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(UI.wrap(r0, 880))
	vb.add_child(UI.label("Il giocatore Ghoul non fa mai punti. Gli Umani:", 19, UI.MUTED))
	for i in results.size():
		var r: Dictionary = results[i]
		var hb := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = UI.seat_col(engine, r["seat"])
		sw.custom_minimum_size = Vector2(14, 40)
		hb.add_child(sw)
		var l := UI.label("  %d. %s" % [i + 1, engine.pname(r["seat"])], 26, Color.WHITE, UI.font_bold)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		var det := "obiettivi intatti +%d · ghoul eliminati +%d · devastati −%d" % [r["pos"], r["kills"], r["neg"]] if not gw else "obiettivi devastati −%d" % r["neg"]
		hb.add_child(UI.label(det + "   ", 19, UI.MUTED))
		hb.add_child(UI.label("%d" % r["total"], 30, UI.ACID, UI.font_bold))
		vb.add_child(hb)
	if not gw and not results.is_empty():
		var best: int = results[0]["seat"]
		var gl := UI.label("«Gran Trucidatore di Ghouls»: %s" % engine.pname(best), 24, UI.ACID_L, UI.font_semi)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(gl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var again := UI.primary(UI.button("Nuova partita", 300, 56))
	again.pressed.connect(func(): main.show_menu())
	row.add_child(again)
	var stay := UI.button("Guarda le fogne", 300, 56)
	stay.pressed.connect(func(): shade.queue_free())
	row.add_child(stay)
	vb.add_child(row)


# ================================================================ online

func online_waiting(s: int, slow: bool) -> void:
	if s < 0:
		status_lbl.text = ""
	else:
		status_lbl.text = "Aspetto %s…%s" % [engine.pname(s), " (lento)" if slow else ""]


func online_status(t: String) -> void:
	status_lbl.text = t


func online_cancel_decision(t: String) -> void:
	pending = {}
	dec_panel.visible = false
	status_lbl.text = t
	_refresh()


func online_caught_up() -> void:
	status_lbl.text = "Partita ripresa."


# ================================================================ controlli disegnati

class DiceBox extends Control:
	var view

	func _draw() -> void:
		var e: GHEngine = view.engine
		if e.dice.is_empty():
			return
		var x := 0.0
		for v in e.dice:
			UI.draw_die(self, Rect2(Vector2(x, 4), Vector2(38, 38)), int(v), e.dice.size() == 2 or e.phase == "inizio")
			x += 44.0


class ObjCard extends Control:
	var view
	var key := ""
	var hl := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			view._on_loc_click("o:" + key)

	func _draw() -> void:
		var e: GHEngine = view.engine
		var o: Dictionary = e.objs[key]
		var dev: bool = o["dev"]
		var ow: int = o["owner"]
		var r := Rect2(Vector2.ZERO, size)
		var bc := UI.seat_col(e, ow) if ow >= 1 else Color("#3b4030")
		draw_style_box(UI.panel_style(Color("#1b0d0b") if dev else UI.PANEL_L, bc, 3 if ow >= 1 else 1, 6), r)
		draw_texture_rect(UI.obj_tex(key, dev), Rect2(Vector2(4, 4), Vector2(144, 96)), false, Color(1, 1, 1) if not dev else Color(0.9, 0.75, 0.75))
		var f := UI.font_bold
		var nm: String = D.OBJECTIVES[key]["name"]
		draw_string(f, Vector2(156, 24), nm, HORIZONTAL_ALIGNMENT_LEFT, 150, 17 if nm.length() < 16 else 14, Color.WHITE)
		draw_string(UI.font_title, Vector2(size.x - 44, 30), "×%d" % D.OBJECTIVES[key]["mult"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.ACID)
		if dev:
			draw_string(UI.font_title, Vector2(156, 58), "DEVASTATO", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.BLOOD_L)
		var l := "o:" + key
		var pieces := e.ids_at(l, "VFPMR")
		var x := 156.0
		var y := 64.0 if dev else 34.0
		if view.sees_obj():
			var n := 0
			for id in pieces:
				if n >= 14:
					break
				draw_texture_rect(UI.counter_tex(e.cs[id]), Rect2(Vector2(x, y), Vector2(28, 28)), false)
				x += 29.0
				n += 1
				if n == 7:
					x = 156.0
					y += 30.0
			if pieces.size() > 14:
				draw_string(f, Vector2(156 + 7 * 29, y + 20), "+%d" % (pieces.size() - 14), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.ACID)
			var val := e.obj_value(key)
			if val > 0:
				draw_string(f, Vector2(size.x - 60, size.y - 8), "%d pt" % val, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.ACID_L)
		elif not pieces.is_empty():
			draw_texture_rect(UI.human_back(), Rect2(Vector2(x, y), Vector2(32, 32)), false)
			draw_string(f, Vector2(x + 40, y + 24), "%d pedine coperte" % pieces.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.BONE)
		var gh := e.ghouls_at(l)
		if not gh.is_empty():
			var gp := Vector2(size.x - 92, size.y - 40)
			draw_texture_rect(UI.ghoul_back(), Rect2(gp, Vector2(30, 30)), false)
			draw_string(f, gp + Vector2(36, 23), "×%d" % gh.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.GHOUL_C)
		if hl != "":
			var col: Color = UI.SLIME if hl == "src" or hl == "sel" else UI.ACID
			draw_rect(r.grow(-2), col, false, 4.0)
		if e.combat.get("loc", "") == l:
			draw_rect(r.grow(-6), UI.BLOOD_L, false, 3.0)


class TransRow extends Control:
	var view
	var seat := 1
	var hl := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			view._on_loc_click("t:%d" % seat)

	func _draw() -> void:
		var e: GHEngine = view.engine
		var col := UI.seat_col(e, seat)
		var r := Rect2(Vector2.ZERO, size)
		var active: bool = e.active_human == seat
		draw_style_box(UI.panel_style(col.darkened(0.78), col if active else col.darkened(0.3), 3 if active else 2, 6), r)
		draw_texture_rect(UI.tex("res://assets/misc/trasporto.jpg"), Rect2(Vector2(4, 4), Vector2(150, 70)), false)
		draw_rect(Rect2(Vector2(4, 4), Vector2(150, 70)), Color(col, 0.25))
		var f := UI.font_bold
		draw_string(f, Vector2(164, 26), e.pname(seat), HORIZONTAL_ALIGNMENT_LEFT, 200, 19, Color.WHITE)
		# segnalini numerati
		var used: Array = e.tokens_used[seat]
		for v in range(1, 6):
			var p := Vector2(164 + (v - 1) * 24, 38)
			var on := not used.has(v)
			draw_rect(Rect2(p, Vector2(20, 20)), col if on else Color(0.2, 0.2, 0.2))
			draw_string(f, p + Vector2(5, 16), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK if on else Color(0.45, 0.45, 0.45))
		if e.played.has(seat) and e.phase != "numeri":
			draw_string(UI.font_title, Vector2(292, 58), str(e.played[seat]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
		draw_string(f, Vector2(164, 74), "☠ %d" % e.kills[seat], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.ACID_L)
		var x := 330.0
		var on_t := e.ids_at("t:%d" % seat)
		for i in on_t.size():
			if x + 46 > size.x - 8 and i < on_t.size() - 1:
				draw_string(f, Vector2(x + 2, 46), "+%d" % (on_t.size() - i), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
				break
			draw_texture_rect(UI.counter_tex(e.cs[on_t[i]]), Rect2(Vector2(x, 16), Vector2(44, 44)), false)
			x += 46.0
		if hl != "":
			draw_rect(r.grow(-2), UI.SLIME if hl == "src" else UI.ACID, false, 4.0)


class CombatCounter extends Control:
	signal pressed
	var view
	var id := 0
	var face := true
	var badge := 0
	var selected := false
	var clickable := false
	var dim := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if clickable and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func _draw() -> void:
		var e: GHEngine = view.engine
		var c: Dictionary = e.cs[id]
		var ghoul: bool = c["t"] == "G" or c["t"] == "S"
		var tex := UI.counter_tex(c) if face else UI.ghoul_back()
		var mod := Color(0.5, 0.5, 0.5) if dim else Color.WHITE
		draw_texture_rect(tex, Rect2(Vector2(4, 4), Vector2(84, 84)), false, mod)
		var bc := UI.GHOUL_C if ghoul else UI.seat_col(e, maxi(1, int(c["o"])))
		draw_rect(Rect2(Vector2(4, 4), Vector2(84, 84)), bc, false, 2.0)
		if selected:
			draw_rect(Rect2(Vector2(1, 1), Vector2(90, 90)), UI.ACID, false, 4.0)
		elif clickable:
			draw_rect(Rect2(Vector2(1, 1), Vector2(90, 90)), Color(UI.ACID, 0.4), false, 2.0)
		var f := UI.font_bold
		var txt := ""
		if ghoul:
			txt = ("forza %d" % e.gval(id)) if face else "?"
		elif c["t"] == "V":
			var rg := e.hranged(id)
			txt = "D %s · C %d" % ["—" if rg < 0 else str(rg), e.hmelee(id)]
		else:
			txt = "C 0"
		var sw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, Vector2(46 - sw * 0.5, 112), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.BONE)
		if badge > 0:
			var bp := Vector2(80, 12)
			draw_circle(bp, 15, Color.BLACK)
			draw_circle(bp, 13, Color.from_hsv(fmod(badge * 0.17, 1.0), 0.75, 0.9))
			var t2 := str(badge)
			var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(f, bp + Vector2(-w2 * 0.5, 7), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK)


class LastAttack extends Control:
	var data: Dictionary

	func _draw() -> void:
		var f := UI.font_bold
		var h := "Umani: %s" % ", ".join(data["h"])
		draw_string(f, Vector2(0, 22), h, HORIZONTAL_ALIGNMENT_LEFT, 360, 17, UI.ACID_L)
		draw_string(f, Vector2(0, 50), "%d +" % data["hs"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		UI.draw_die(self, Rect2(Vector2(54, 28), Vector2(32, 32)), int(data["hd"]), false)
		draw_string(f, Vector2(94, 50), "= %d" % (int(data["hs"]) + int(data["hd"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		draw_string(f, Vector2(380, 22), "Ghoul: %s" % "+".join(data["g"]), HORIZONTAL_ALIGNMENT_LEFT, 300, 17, UI.GHOUL_C)
		draw_string(f, Vector2(380, 50), "%d +" % data["gs"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		UI.draw_die(self, Rect2(Vector2(434, 28), Vector2(32, 32)), int(data["gd"]), true)
		draw_string(f, Vector2(474, 50), "= %d" % (int(data["gs"]) + int(data["gd"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		draw_string(UI.font_title, Vector2(640, 48), str(data["out"]), HORIZONTAL_ALIGNMENT_LEFT, 380, 24, UI.BLOOD_L if str(data["out"]).contains("umani") else UI.SLIME)

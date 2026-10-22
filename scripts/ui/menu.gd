extends Control
## Menu principale: quanti giocatori umani difendono la città, chi guida i Ghoul e ogni colore
## (persona o IA), alba (limite di turni), velocità dell'IA e gioco online.

const D = preload("res://scripts/data/gh_data.gd")
const MODES := ["Persona", "IA facile", "IA normale", "IA difficile"]
const DAWN := [20, 30, 40, 0]
const SEAT_KEYS := ["ghoul", "rosso", "verde", "giallo"]

var main
var page: Control
var nh := 2
var modes := {}                 # posto -> 0..3
var names := {}
var speed := 1
var dawn := 1
var style := 0                  # 0 classica (scansioni del 1992), 1 Reborn
var view3d := 1
var msg: Label
var seats_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = main.menu_state
	if not st.is_empty():
		nh = st["nh"]
		modes = st["modes"].duplicate()
		names = st["names"].duplicate()
		speed = st["speed"]
		dawn = st["dawn"]
		style = st.get("style", 0)
		view3d = st.get("view3d", 1)
	for k in SEAT_KEYS:
		if not modes.has(k):
			modes[k] = 0 if k == "rosso" else 2
		if not names.has(k):
			names[k] = "Ghoul" if k == "ghoul" else D.COLOR_NAME[k]
	_background()
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)

	var cover := UI.icon_rect(UI.tex("res://assets/misc/copertina.jpg"), Vector2(640, 870))
	cover.position = Vector2(50, 70)
	page.add_child(cover)
	var tag := UI.label("Un'orda di Ghouls sale dalle fogne per conquistare la città e la Cattedrale.\nDifendetela, finché siete vivi.", 22, UI.BONE)
	tag.position = Vector2(50, 950)
	tag.size = Vector2(640, 70)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("outline_size", 5)
	page.add_child(tag)

	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.dark_style(10, 0.9))
	right.position = Vector2(740, 70)
	right.custom_minimum_size = Vector2(1130, 750)
	page.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right.add_child(rv)
	rv.add_child(UI.heading("Chi gioca", 30, UI.ACID))
	rv.add_child(_segmented("Giocatori", ["3 (1 Ghoul + 2 Umani)", "4 (1 Ghoul + 3 Umani)"], nh - 2, func(k):
		nh = k + 2
		msg.text = ""
		_refresh_seats(), 330))
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 8)
	rv.add_child(seats_box)
	rv.add_child(HSeparator.new())
	rv.add_child(UI.heading("Opzioni", 26, UI.ACID))
	var dr := _segmented("Alba", ["turno 20", "turno 30", "turno 40", "mai"], dawn, func(k): dawn = k, 160)
	dr.tooltip_text = "Regola aggiunta in questa versione: se la Cattedrale resiste fino all'alba,\ni Ghouls si ritirano nelle fogne e vincono gli Umani."
	rv.add_child(dr)
	rv.add_child(_segmented("Velocità IA", ["Lenta", "Normale", "Veloce", "Istantanea"], speed, func(k): speed = k, 160))
	var gr := _segmented("Grafica", ["Classica 1992", "Reborn"], style, func(k): style = k, 250)
	gr.tooltip_text = "Reborn: la nuova grafica (assets/reborn); dove manca un'immagine nuova si usa quella originale."
	rv.add_child(gr)
	rv.add_child(_segmented("Vista", ["2D", "3D: città e fogne"], view3d, func(k): view3d = k, 250))

	msg = UI.label("", 24, UI.BLOOD_L, UI.font_bold)
	msg.position = Vector2(740, 1000)
	page.add_child(msg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(740, 862)
	page.add_child(btns)
	var b_start := _big_button("Si scende nelle fogne", 520, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 230)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	var b_online := _big_button("Gioca online", 340)
	b_online.pressed.connect(_online_panel)
	btns.add_child(b_online)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 150)
		b_quit.pressed.connect(func(): get_tree().quit())
		page.add_child(b_quit)
		b_quit.position = Vector2(1720, 940)
	var credits := UI.label("Ghouls © Stefano Ancillai e Marco Ramadori · disegni di Luigi Filipponi · Devil's Den, Roma 1992 · F11 schermo intero", 17, Color("#7f8070"))
	credits.position = Vector2(740, 1046)
	page.add_child(credits)
	_refresh_seats()
	if not main.lobby.is_empty():
		_online_panel.call_deferred()


func _background() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var tr := TextureRect.new()
	tr.texture = UI.tex("res://assets/tiles/t02.jpg")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.modulate = Color(0.16, 0.19, 0.13)
	add_child(tr)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.02, 0.35))
	g.set_color(1, Color(0.02, 0.03, 0.02, 0.92))
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.45)
	grad.fill_to = Vector2(1.0, 1.0)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)


func _center() -> void:
	var vs := get_viewport_rect().size
	page.position = ((vs - page.size) * 0.5).floor()
	page.position.y = maxf(0.0, page.position.y)


func _store() -> void:
	main.menu_state = {"nh": nh, "modes": modes.duplicate(), "names": names.duplicate(), "speed": speed, "dawn": dawn, "style": style, "view3d": view3d}


func _seat_keys() -> Array:
	return SEAT_KEYS.slice(0, nh + 1)


func _refresh_seats() -> void:
	for c in seats_box.get_children():
		c.queue_free()
	for k in _seat_keys():
		var col: Color = UI.GHOUL_C if k == "ghoul" else UI.pcol(k)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_style(Color(col.darkened(0.72), 0.92), col, 2, 8))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		var ic := UI.icon_rect(UI.tex("res://assets/counters/g5.png") if k == "ghoul" else UI.tex("res://assets/misc/trasporto.jpg"), Vector2(96 if k != "ghoul" else 60, 60))
		hb.add_child(ic)
		var vb := VBoxContainer.new()
		vb.custom_minimum_size.x = 330
		vb.add_child(UI.label("Il Ghoul — guida le orde" if k == "ghoul" else "Umani — %s" % D.COLOR_NAME[k], 21, Color.WHITE, UI.font_bold))
		var le := LineEdit.new()
		le.text = names[k]
		le.max_length = 20
		le.custom_minimum_size = Vector2(300, 40)
		le.add_theme_font_size_override("font_size", 20)
		var kk: String = k
		le.text_changed.connect(func(t): names[kk] = t)
		vb.add_child(le)
		hb.add_child(vb)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 4)
		hb.add_child(bar)
		for m in MODES.size():
			var b := Button.new()
			b.text = MODES[m]
			b.custom_minimum_size = Vector2(150, 52)
			b.add_theme_font_size_override("font_size", 18)
			var on: bool = modes[k] == m
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.SLIME if on else Color("#191d13"), UI.SLIME if on else Color("#373e2a"), 2, 4))
			b.add_theme_color_override("font_color", UI.INK if on else UI.TEXT)
			b.add_theme_color_override("font_hover_color", UI.INK if on else UI.ACID_L)
			var mm := m
			b.pressed.connect(func():
				modes[kk] = mm
				msg.text = ""
				_refresh_seats())
			bar.add_child(b)
		seats_box.add_child(row)


func _segmented(label_text: String, items: Array, cur: int, cb: Callable, w := 200) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 22, Color.WHITE, UI.font_bold)
	l.custom_minimum_size = Vector2(170, 0)
	hb.add_child(l)
	var btns := []
	for k in range(items.size()):
		var b := Button.new()
		b.text = items[k]
		b.custom_minimum_size = Vector2(w, 46)
		b.add_theme_font_size_override("font_size", 19)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			var on: bool = k == sel
			btns[k].add_theme_stylebox_override("normal", UI.panel_style(UI.SLIME if on else Color("#191d13"), UI.SLIME if on else Color("#373e2a"), 2, 4))
			btns[k].add_theme_color_override("font_color", UI.INK if on else UI.TEXT)
			btns[k].add_theme_color_override("font_hover_color", UI.INK if on else UI.ACID_L)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 80)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 36)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for k in _seat_keys():
		var m: int = modes[k]
		var nm: String = names[k].strip_edges()
		if nm == "":
			nm = "Ghoul" if k == "ghoul" else D.COLOR_NAME[k]
		seats.append({"name": nm, "ai": m != 0, "level": maxi(0, m - 1)})
	var speeds := [1.1, 0.55, 0.15, 0.0]
	return {"seats": seats, "ai_delay": speeds[speed], "max_turns": DAWN[dawn], "style": "reborn" if style == 1 else "classico", "view3d": view3d == 1}


func _on_start() -> void:
	_store()
	main.start_game(_config())


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.dark_style(10, 0.98))
	box.position = page.position + Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 54))
	var info := UI.label("Chi crea la stanza sceglie prima nel menu il numero di giocatori: i posti su PERSONA diventano i posti per gli amici (il primo è il suo). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA.", 20, Color("#cccccc"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := UI.button("Crea una stanza", 0, 60, 24)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.button("Entra", 200, 60, 24)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 21, Color.WHITE)
	on_lbl.custom_minimum_size = Vector2(760, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Inizia online", 420, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 300)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seat_label(i: int) -> String:
	return "Ghoul" if i == 0 else D.COLOR_NAME[SEAT_KEYS[i]]


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parts.append("%s: %s" % [_seat_label(int(idx)), who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := []
	var list: Array = _config()["seats"]
	for i in list.size():
		if not list[i]["ai"]:
			seats.append(i)
	if seats.size() < 2:
		_say("Metti su PERSONA almeno due posti: il primo è il tuo, gli altri sono per gli amici.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Inizia online: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto: %s).\nAspetta che chi l'ha creata avvii la partita." % [code, _seat_label(int(main.lobby["seat"]))])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: giocatori, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato i giocatori dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)

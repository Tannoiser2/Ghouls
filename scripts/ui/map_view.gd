class_name MapView
extends Control
## Le fogne: tessere piazzate, pile di pedine, tombini con la pedina Locazione, caselle da esplorare.
## Rotella = zoom, trascinamento = spostamento. Disegnata tutta in _draw.

signal loc_clicked(loc: String)
signal tomb_clicked(loc: String, objkey: String)

const D = preload("res://scripts/data/gh_data.gd")
const T := 168.0

var eng: GHEngine
var view                         # vista di gioco: prospettiva (Ghoul / Umani)
var zoom := 1.0
var pan := Vector2.ZERO
var allowed: Dictionary = {}     # loc -> true (tessere, caselle nuove)
var allowed_tombs: Dictionary = {} # "c:x,y|chiave" -> true
var source := ""
var ghost: Array = []            # [kind, x, y, rot]
var focus := ""
var _drag := false
var _drag_from := Vector2.ZERO
var _moved := 0.0
var _hover := ""
var _fitted := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func redraw() -> void:
	queue_redraw()


func set_engine(e: GHEngine) -> void:
	eng = e
	queue_redraw()


func fit() -> void:
	if eng == null or size.x < 10:
		return
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for key in eng.tiles:
		var p := GHEngine.cell("c:" + key)
		mn = mn.min(Vector2(p) - Vector2.ONE)
		mx = mx.max(Vector2(p) + Vector2.ONE * 2)
	var w := (mx - mn) * T
	# la barra delle decisioni copre il fondo della mappa: si inquadra la parte alta
	var area := Vector2(size.x, size.y * 0.74)
	zoom = clampf(minf(area.x / w.x, area.y / w.y), 0.35, 1.1)
	var center := (mn + mx) * 0.5 * T
	pan = area * 0.5 - center * zoom
	_fitted = true
	queue_redraw()


func ensure_visible() -> void:
	# l'inquadratura si fa solo la prima volta (e con il pulsante Centra): poi resta dove la mette il giocatore
	if not _fitted:
		fit()


func _cell_rect(p: Vector2i) -> Rect2:
	return Rect2(pan + Vector2(p) * T * zoom, Vector2.ONE * T * zoom)


func _cell_at(pos: Vector2) -> Vector2i:
	var w := (pos - pan) / (T * zoom)
	return Vector2i(floori(w.x), floori(w.y))


## Posizione del tombino i sulla tessera (in frazioni), seguendo il disegno ruotato.
func _tomb_pos(t: Dictionary, i: int) -> Vector2:
	var tp: Array = D.TILES[t["k"]].get("tp", [[0.82, 0.18], [0.18, 0.82]])
	var p := Vector2(tp[i % tp.size()][0], tp[i % tp.size()][1])
	for r in posmod(int(t["r"]), 4):
		p = Vector2(1.0 - p.y, p.x)
	return p


func _draw() -> void:
	if eng == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#07090a"))
	# griglia leggera
	var step := T * zoom
	var grid := Color(0.35, 0.45, 0.25, 0.06)
	var x0 := fposmod(pan.x, step)
	while x0 < size.x:
		draw_line(Vector2(x0, 0), Vector2(x0, size.y), grid)
		x0 += step
	var y0 := fposmod(pan.y, step)
	while y0 < size.y:
		draw_line(Vector2(0, y0), Vector2(size.x, y0), grid)
		y0 += step
	var font := UI.font_bold
	for key in eng.tiles:
		var t: Dictionary = eng.tiles[key]
		var p := GHEngine.cell("c:" + key)
		var r := _cell_rect(p)
		_draw_tile(UI.tile_tex(t["k"]), r, int(t["r"]), Color.WHITE)
		var loc: String = "c:" + key
		if t["k"] == "covo" or t["k"] == "cimitero":
			var nm: String = "COVO" if t["k"] == "covo" else "CIMITERO"
			var fs := int(26 * zoom)
			var tw := UI.font_title.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(UI.font_title, r.position + Vector2((r.size.x - tw) * 0.5, r.size.y - 8 * zoom), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(6 * zoom), Color(0, 0, 0, 0.9))
			draw_string(UI.font_title, r.position + Vector2((r.size.x - tw) * 0.5, r.size.y - 8 * zoom), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.BLOOD_L if t["k"] == "covo" else UI.BONE)
		if allowed.has(loc):
			_glow(r, UI.ACID)
		if loc == source:
			_glow(r, UI.SLIME)
		if loc == focus:
			_glow(r, UI.BLOOD_L)
		if loc == _hover and (allowed.has(loc) or not view.pending.is_empty()):
			draw_rect(r, Color(1, 1, 1, 0.06))
	# caselle da esplorare / piazzamenti possibili
	for loc in allowed:
		if not loc.begins_with("c:"):
			continue
		if eng.tiles.has(loc.substr(2)):
			continue
		var r2 := _cell_rect(GHEngine.cell(loc))
		draw_rect(r2.grow(-6 * zoom), Color(UI.ACID, 0.12))
		_dashed(r2.grow(-6 * zoom), UI.ACID)
		var c := r2.get_center()
		draw_line(c - Vector2(16, 0) * zoom, c + Vector2(16, 0) * zoom, UI.ACID, 3)
		draw_line(c - Vector2(0, 16) * zoom, c + Vector2(0, 16) * zoom, UI.ACID, 3)
	if not ghost.is_empty():
		var gr := _cell_rect(Vector2i(ghost[1], ghost[2]))
		_draw_tile(UI.tile_tex(ghost[0]), gr, int(ghost[3]), Color(1, 1, 1, 0.82))
		_glow(gr, UI.SLIME)
	# tombini
	for key in eng.tiles:
		var t: Dictionary = eng.tiles[key]
		var r := _cell_rect(GHEngine.cell("c:" + key))
		for i in (t["tomb"] as Array).size():
			var k: String = t["tomb"][i]
			var c := r.position + _tomb_pos(t, i) * r.size
			var rad := 17.0 * zoom + 4
			var txt := "—"
			var col := Color("#5a5a50")
			if k != "":
				if view.sees_tomb(k):
					txt = _short(k)
					col = UI.BLOOD if eng.objs[k]["dev"] else Color("#2b5d8c")
				else:
					txt = "?"
					col = Color("#4b3d6e")
			var on := allowed_tombs.has("c:%s|%s" % [key, k])
			draw_circle(c, rad + (4 if on else 2), UI.ACID if on else Color(0, 0, 0, 0.85))
			draw_circle(c, rad, col)
			var fs := int(15 * zoom + 5)
			var sw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, c + Vector2(-sw.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# pile di pedine
	for key in eng.tiles:
		var loc: String = "c:" + key
		var r := _cell_rect(GHEngine.cell(loc))
		var gh := eng.ghouls_at(loc)
		var hu := eng.ids_at(loc, "VFR")
		if not gh.is_empty():
			_stack(gh, r.position + Vector2(0.08, 0.30) * r.size, true)
		if not hu.is_empty():
			_stack(hu, r.position + Vector2(0.50, 0.30) * r.size, false)


func _short(k: String) -> String:
	return {"cattedrale": "CAT", "ospedale": "OSP", "polizia": "POL", "radiotv": "TV", "universita": "UNI",
		"residenziali": "RES", "porto": "POR", "popolari": "POP", "sportivo": "SPO", "commerciale": "COM"}[k]


func _draw_tile(tex: Texture2D, r: Rect2, rot: int, mod: Color) -> void:
	var c := r.get_center()
	draw_set_transform(c, rot * PI * 0.5, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-r.size * 0.5, r.size), false, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(r, Color(0, 0, 0, 0.55), false, 1.0)


func _glow(r: Rect2, col: Color) -> void:
	draw_rect(r.grow(-2), Color(col, 0.9), false, 4.0)
	draw_rect(r.grow(-7), Color(col, 0.35), false, 3.0)


func _dashed(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, 2.0, 10.0)


func _stack(ids: Array, at: Vector2, ghoul: bool) -> void:
	var sz := 50.0 * zoom + 6
	var n := ids.size()
	var show := mini(n, 4)
	for i in show:
		var id: int = ids[i]
		var pos := at + Vector2(i * sz * 0.22, i * sz * 0.16)
		var tex: Texture2D
		if ghoul:
			tex = UI.counter_tex(eng.cs[id]) if view.sees_ghoul(id) else UI.ghoul_back()
		else:
			tex = UI.counter_tex(eng.cs[id])
		draw_rect(Rect2(pos + Vector2(3, 3), Vector2(sz, sz)), Color(0, 0, 0, 0.55))
		draw_texture_rect(tex, Rect2(pos, Vector2(sz, sz)), false)
		var bc := UI.GHOUL_C if ghoul else UI.seat_col(eng, maxi(1, int(eng.cs[id]["o"])))
		draw_rect(Rect2(pos, Vector2(sz, sz)), bc, false, 2.0)
	if n > 1:
		var bp := at + Vector2(show * sz * 0.22 + sz * 0.75, -4)
		draw_circle(bp, 15 * zoom + 5, Color(0, 0, 0, 0.9))
		draw_circle(bp, 13 * zoom + 4, UI.GHOUL_C.darkened(0.3) if ghoul else UI.BLOOD)
		var fs := int(14 * zoom + 7)
		var txt := str(n)
		var sw := UI.font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(UI.font_bold, bp + Vector2(-sw.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_drag = true
				_drag_from = mb.position
				_moved = 0.0
			else:
				_drag = false
				if _moved < 8.0 and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag:
			pan += mm.relative
			_moved += mm.relative.length()
			queue_redraw()
		_hover_at(mm.position)
	elif ev is InputEventMagnifyGesture:
		_zoom_at((ev as InputEventMagnifyGesture).position, (ev as InputEventMagnifyGesture).factor)
	elif ev is InputEventPanGesture:
		pan -= (ev as InputEventPanGesture).delta * 12
		queue_redraw()


func _zoom_at(p: Vector2, f: float) -> void:
	var nz := clampf(zoom * f, 0.3, 2.2)
	pan = p - (p - pan) * (nz / zoom)
	zoom = nz
	queue_redraw()


func _click(pos: Vector2) -> void:
	var p := _cell_at(pos)
	var key := "%d,%d" % [p.x, p.y]
	# prima i tombini
	if eng.tiles.has(key):
		var r := _cell_rect(p)
		var t: Dictionary = eng.tiles[key]
		for i in (t["tomb"] as Array).size():
			var c := r.position + _tomb_pos(t, i) * r.size
			if pos.distance_to(c) < 22.0 * zoom + 6 and t["tomb"][i] != "":
				tomb_clicked.emit("c:" + key, t["tomb"][i])
				return
	loc_clicked.emit("c:" + key)


func _hover_at(pos: Vector2) -> void:
	var p := _cell_at(pos)
	var loc := "c:%d,%d" % [p.x, p.y]
	if loc != _hover:
		_hover = loc
		tooltip_text = view.tile_tooltip(loc) if eng != null else ""
		queue_redraw()

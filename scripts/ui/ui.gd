class_name UI
extends RefCounted
## Helper grafici condivisi. Palette «fogna e sangue»: nero di fogna, verde melma, arancio acido della
## scritta in copertina, rosso sangue, carta ingiallita. Titoli in Creepster (lettere che colano, come
## il logo della scatola), testi in Jost (geometrico come il Futura del regolamento). Caratteri OFL.

const D = preload("res://scripts/data/gh_data.gd")

const BG := Color("#0a0c08")
const PANEL := Color("#14170f")
const PANEL_L := Color("#20251a")
const SLIME := Color("#a6d23c")
const SLIME_D := Color("#52691d")
const ACID := Color("#f5a623")
const ACID_L := Color("#ffd166")
const BLOOD := Color("#8e1c1c")
const BLOOD_L := Color("#d33b2c")
const BONE := Color("#ece4cc")
const PAPER := Color("#e7dcc0")
const INK := Color("#22180f")
const TEXT := Color("#e9e4d4")
const MUTED := Color("#9c9a88")
const GHOUL_C := Color("#9b7be0")

static var _tex := {}
static var font_title: Font
static var font_body: Font
static var font_bold: Font
static var font_semi: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/Creepster-Regular.ttf")
	var jost: FontFile = load("res://assets/fonts/Jost.ttf")
	font_body = _var(jost, 420)
	font_semi = _var(jost, 560)
	font_bold = _var(jost, 700)


static func _var(f: Font, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = f
	fv.variation_opentype = {"wght": weight}
	return fv


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func pcol(color: String) -> Color:
	return Color(D.COLOR_HEX.get(color, "#888888"))


static func seat_col(e: GHEngine, s: int) -> Color:
	if s == 0:
		return GHOUL_C
	return pcol(e.players[s]["color"])


## Immagine di una pedina (scoperta).
static func counter_tex(c: Dictionary) -> Texture2D:
	match c["t"]:
		"G":
			return tex("res://assets/counters/g%d.png" % c["v"])
		"S":
			return tex("res://assets/counters/sorpresa.png")
		"V":
			return tex("res://assets/counters/v_%s.png" % c["k"])
		"F":
			return tex("res://assets/counters/folla.png")
		"P":
			return tex("res://assets/counters/pv%d.png" % c["v"])
		"M":
			return tex("res://assets/counters/mina%d.png" % c["v"])
		"R":
			return tex("res://assets/counters/radio.png")
		"X":
			return tex("res://assets/counters/rinforzo.png")
	return tex("res://assets/counters/human_back.png")


static func ghoul_back() -> Texture2D:
	return tex("res://assets/counters/ghoul_back.png")


static func human_back() -> Texture2D:
	return tex("res://assets/counters/human_back.png")


static func tile_tex(kind: String) -> Texture2D:
	return tex("res://assets/tiles/t%02d.jpg" % D.TILES[kind]["img"])


static func obj_tex(k: String, dev: bool) -> Texture2D:
	return tex("res://assets/objectives/%s%s.jpg" % [k, "_dev" if dev else ""])


static func panel_style(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


static func dark_style(radius := 8, alpha := 0.95) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), SLIME_D, 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 8
	return sb


static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 40, col := ACID) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.02, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(SLIME_D, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l


static func heading(text: String, size := 22, col := SLIME) -> Label:
	init_fonts()
	return label(text, size, col, font_bold)


static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 50.0, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func primary(b: Button) -> Button:
	var n := panel_style(BLOOD, ACID, 2, 6)
	n.shadow_color = Color(0, 0, 0, 0.45)
	n.shadow_size = 4
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", panel_style(Color("#b22a22"), ACID_L, 2, 6))
	b.add_theme_stylebox_override("pressed", panel_style(ACID, ACID, 2, 6))
	b.add_theme_color_override("font_color", Color("#fff3dc"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


## Dado: faccia chiara (Umani) o verde melma (Ghoul).
static func draw_die(ci: CanvasItem, rect: Rect2, v: int, ghoul: bool) -> void:
	var bg := Color("#3c4a22") if ghoul else Color("#efe6cf")
	var pip := Color("#c8f060") if ghoul else Color("#7e1a14")
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(rect.size.x * 0.18))
	sb.border_color = Color(0, 0, 0, 0.85)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 3
	ci.draw_style_box(sb, rect)
	var c := rect.get_center()
	var o := rect.size.x * 0.25
	var r := rect.size.x * 0.09
	var pos := {
		1: [Vector2.ZERO], 2: [Vector2(-o, -o), Vector2(o, o)], 3: [Vector2(-o, -o), Vector2.ZERO, Vector2(o, o)],
		4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
		5: [Vector2(-o, -o), Vector2(o, -o), Vector2.ZERO, Vector2(-o, o), Vector2(o, o)],
		6: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, 0), Vector2(o, 0), Vector2(-o, o), Vector2(o, o)],
	}
	for p in pos.get(v, []):
		ci.draw_circle(c + p, r, pip)


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#232a19")
	sb.border_color = SLIME_D
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("#34401f")
	sbh.border_color = SLIME
	th.set_stylebox("hover", "Button", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = SLIME
	th.set_stylebox("pressed", "Button", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color("#15180f")
	sbd.border_color = Color("#2c3222")
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", BONE)
	th.set_color("font_hover_color", "Button", ACID_L)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("#5d6052"))
	th.set_font("font", "Button", font_semi)
	th.set_font_size("font_size", "Button", 20)
	th.set_color("font_color", "Label", TEXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_body)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		th.set_font_size(k, "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("font", "LineEdit", font_semi)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_stylebox("normal", "LineEdit", panel_style(Color("#0c0e09"), SLIME_D, 1, 4))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#0c0e09"), SLIME, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 18)
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color("#0e110bf0")
	tp.border_color = SLIME
	tp.set_border_width_all(1)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(SLIME_D, 0.85)
	sc.set_corner_radius_all(4)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(k, "VScrollBar", sc)
	var sct := StyleBoxFlat.new()
	sct.bg_color = Color(0, 0, 0, 0.3)
	th.set_stylebox("scroll", "VScrollBar", sct)
	return th

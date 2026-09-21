extends Control
## Everything in screen space: the fuel bar, the floor name, and the title,
## pause, death and ending screens. Buttons are rebuilt every frame as they
## are drawn, so the keyboard and the mouse always agree on what is where.

const LanternTex: Texture2D = preload("res://assets/sprites/lantern.png")

const WARM := Color(1.0, 0.82, 0.48)
const PALE := Color(0.72, 0.74, 0.86)
const DIM := Color(0.42, 0.44, 0.56)
const VIOLET := Color(0.78, 0.72, 1.0)
const BLUE := Color(0.55, 0.70, 1.0)
const BACK := Color(0.12, 0.11, 0.18, 0.85)
const PANEL := Color(0.07, 0.07, 0.12, 0.94)
const EDGE := Color(0.34, 0.32, 0.47, 0.9)

var font: Font
var game
var flash_col := Color(0, 0, 0, 0)
var note := ""
var note_sub := ""
var note_t := 0.0
var pulse := 0.0
var fade := 0.0
var fade_target := 0.0

var menu_index := 0
var _btns: Array = []


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	flash_col.a = maxf(0.0, flash_col.a - delta * 1.9)
	note_t = maxf(0.0, note_t - delta)
	fade = move_toward(fade, fade_target, delta * 2.5)
	pulse += delta
	queue_redraw()


func flash(c: Color) -> void:
	flash_col = c


func announce(text: String, sub := "", secs := 2.6) -> void:
	note = text
	note_sub = sub
	note_t = secs


# ------------------------------------------------------------- menu plumbing ---
func menu_reset() -> void:
	menu_index = 0


func menu_move(d: int) -> void:
	if _btns.is_empty():
		return
	menu_index = wrapi(menu_index + d, 0, _btns.size())
	Sfx.play_var("blip", -24.0)


func menu_current() -> String:
	if _btns.is_empty() or menu_index >= _btns.size():
		return ""
	return _btns[menu_index]["id"]


func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseMotion:
		for i in _btns.size():
			var r: Rect2 = _btns[i]["rect"]
			if r.has_point(event.position):
				menu_index = i
				return
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		for b in _btns:
			var br: Rect2 = b["rect"]
			if br.has_point(event.position):
				game.menu_activate(b["id"])
				return


# ------------------------------------------------------------------ drawing ---
func _shadowed(at: Vector2, s: String, fs: int, col: Color, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, at + Vector2(1, 1), s, align, width, fs, Color(0, 0, 0, 0.72 * col.a))
	draw_string(font, at, s, align, width, fs, col)


func _clock(t: float) -> String:
	var mins := int(t / 60.0)
	var secs := int(t) - mins * 60
	return "%02d:%02d" % [mins, secs]


func _bar(at: Vector2, w: float, h: float, frac: float, fill: Color, back := BACK) -> void:
	draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(at, Vector2(w, h)), back)
	if frac > 0.0:
		draw_rect(Rect2(at, Vector2(w * clampf(frac, 0.0, 1.0), h)), fill)


func _button(rect: Rect2, id: String, label: String, fs: int, sub := "") -> void:
	var idx := _btns.size()
	_btns.append({"id": id, "rect": rect})
	var hot: bool = idx == menu_index
	draw_rect(rect, Color(0.13, 0.12, 0.2, 0.95) if hot else Color(0.07, 0.07, 0.12, 0.9))
	draw_rect(rect, WARM if hot else EDGE, false, 1.0)
	if hot:
		draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), WARM)
	var ty := rect.position.y + rect.size.y * 0.5 + fs * 0.36
	if sub != "":
		ty -= 5
	_shadowed(Vector2(rect.position.x, ty), label, fs, WARM if hot else PALE,
		rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if sub != "":
		_shadowed(Vector2(rect.position.x, ty + 12), sub, 8, DIM,
			rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw() -> void:
	if game == null:
		return
	_btns.clear()
	var vs := get_viewport_rect().size
	var p = game.player
	var in_run: bool = game.state in [game.PLAY, game.DYING, game.PAUSED]

	if is_instance_valid(p) and in_run:
		_draw_fuel(p)
		_draw_floor_info(vs)

	if note_t > 0.0 and game.state != game.MENU:
		var a := clampf(note_t / 0.7, 0.0, 1.0)
		_shadowed(Vector2(0, vs.y - 92), note, 20, Color(WARM.r, WARM.g, WARM.b, a), vs.x, HORIZONTAL_ALIGNMENT_CENTER)
		if note_sub != "":
			_shadowed(Vector2(0, vs.y - 75), note_sub, 11, Color(PALE.r, PALE.g, PALE.b, a), vs.x, HORIZONTAL_ALIGNMENT_CENTER)

	if flash_col.a > 0.002:
		draw_rect(Rect2(Vector2.ZERO, vs), flash_col)
	if fade > 0.002:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.01, 0.02, fade))

	match game.state:
		game.MENU:
			_draw_menu(vs)
		game.PAUSED:
			_draw_pause(vs)
		game.DEAD:
			_draw_death(vs)
		game.WIN:
			_draw_win(vs)


# ------------------------------------------------------------------ play HUD ---
func _draw_fuel(p) -> void:
	var frac: float = p.fuel / p.MAX_FUEL
	var col := Color(1.0, 0.72, 0.28).lerp(Color(0.88, 0.22, 0.28), clampf(1.0 - frac * 2.4, 0.0, 1.0))
	if frac < 0.22 and not p.dark:
		col.a = 0.55 + 0.45 * absf(sin(pulse * 7.0))
	draw_texture_rect(LanternTex, Rect2(10, 9, 14, 18), false,
		Color(1, 1, 1) if not p.dark else Color(0.35, 0.35, 0.45))
	_shadowed(Vector2(30, 16), "LANTERN", 9, DIM)
	_bar(Vector2(30, 20), 140, 8, frac, col)
	var label := "%d%%" % int(ceilf(frac * 100.0)) if not p.dark else "OUT"
	_shadowed(Vector2(176, 28), label, 10, PALE if not p.dark else Color(0.92, 0.36, 0.42))
	if frac < 0.22 and not p.dark:
		_shadowed(Vector2(30, 42), "find oil", 8, Color(0.92, 0.5, 0.45, 0.6 + 0.4 * absf(sin(pulse * 3.5))))


func _draw_floor_info(vs: Vector2) -> void:
	_shadowed(Vector2(vs.x - 210, 17), "DEPTH  %d / %d" % [game.depth, game.level_count()], 13, VIOLET,
		200, HORIZONTAL_ALIGNMENT_RIGHT)
	_shadowed(Vector2(vs.x - 210, 30), String(game.level["name"]), 9, DIM, 200, HORIZONTAL_ALIGNMENT_RIGHT)
	var lit: bool = game.beacon_lit
	var txt := "BEACON LIT" if lit else "BEACON DARK"
	_shadowed(Vector2(vs.x - 210, 43), txt, 8, WARM if lit else DIM, 200, HORIZONTAL_ALIGNMENT_RIGHT)
	_shadowed(Vector2(vs.x - 210, 55), _clock(game.run_time), 8, DIM, 200, HORIZONTAL_ALIGNMENT_RIGHT)


# -------------------------------------------------------------------- menus ---
func _draw_menu(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.06, 0.82))
	_shadowed(Vector2(0, 80), "H A V E N", 40, WARM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	_shadowed(Vector2(0, 102), "the long way down", 12, PALE, vs.x, HORIZONTAL_ALIGNMENT_CENTER)

	var bw := 214.0
	var bh := 30.0
	var x0 := (vs.x - bw) * 0.5
	var y := 134.0
	_button(Rect2(Vector2(x0, y), Vector2(bw, bh)), "play", "PLAY", 16, "start at depth 1")
	y += bh + 8
	if game.can_continue():
		_button(Rect2(Vector2(x0, y), Vector2(bw, bh)), "continue", "CONTINUE", 14,
			"from depth %d" % game.continue_depth())
		y += bh + 8
	if not OS.has_feature("web"):
		_button(Rect2(Vector2(x0, y), Vector2(bw, 24)), "quit", "QUIT", 12)

	if game.best_time > 0.0:
		_shadowed(Vector2(0, vs.y - 40), "best time to the bottom:  %s" % _clock(game.best_time),
			9, WARM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	_shadowed(Vector2(0, vs.y - 26), "move  A D / arrows     jump  SPACE     light a beacon  hold E",
		8, DIM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	_shadowed(Vector2(0, vs.y - 13), "ESC pauses.  R restarts the floor.", 8, DIM,
		vs.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_pause(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.06, 0.72))
	_shadowed(Vector2(0, 110), "P A U S E D", 22, WARM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	_shadowed(Vector2(0, 128), "the dark is patient. it can wait", 9, DIM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	var bw := 200.0
	var x0 := (vs.x - bw) * 0.5
	_button(Rect2(Vector2(x0, 150), Vector2(bw, 26)), "resume", "RESUME", 13)
	_button(Rect2(Vector2(x0, 184), Vector2(bw, 26)), "restart", "RESTART FLOOR", 12)
	_button(Rect2(Vector2(x0, 218), Vector2(bw, 26)), "home", "MAIN MENU", 12)


func _draw_death(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.02, 0.05, 0.9))
	_shadowed(Vector2(0, 104), "THE LANTERN WENT OUT", 22, Color(0.92, 0.36, 0.42),
		vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	_shadowed(Vector2(0, 124), "depth %d, %s" % [game.depth, String(game.level["name"]).to_lower()], 12, VIOLET,
		vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	var line := "the shadows had been waiting for that"
	if game.died_in_pit:
		line = "the drop was deep and the lantern was nearly empty"
	_shadowed(Vector2(0, 140), line, 9, DIM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	var bw := 150.0
	var gap := 12.0
	var x0 := (vs.x - (bw * 2 + gap)) * 0.5
	var restart_label := "FROM THE BEACON" if game.beacon_lit else "TRY AGAIN"
	_button(Rect2(Vector2(x0, 172), Vector2(bw, 28)), "retry", restart_label, 12, "R")
	_button(Rect2(Vector2(x0 + bw + gap, 172), Vector2(bw, 28)), "home", "MAIN MENU", 12, "H")
	_shadowed(Vector2(0, vs.y - 20), "lanterns lost so far:  %d" % game.deaths, 8, DIM,
		vs.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_win(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.06, 0.86))
	_shadowed(Vector2(0, 74), "THE LAST BEACON IS LIT", 22, WARM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	_shadowed(Vector2(0, 94), "it is warm down here, for once", 11, PALE, vs.x, HORIZONTAL_ALIGNMENT_CENTER)

	var pw := 220.0
	var ph := 92.0
	var at := Vector2((vs.x - pw) * 0.5, 110)
	draw_rect(Rect2(at, Vector2(pw, ph)), PANEL)
	draw_rect(Rect2(at, Vector2(pw, ph)), EDGE, false, 1.0)
	var rows := [
		["time", _clock(game.run_time)],
		["lanterns lost", str(game.deaths)],
		["oil flasks drunk", str(game.flasks_taken)],
		["best time", _clock(game.best_time)],
	]
	var y := at.y + 22.0
	for r in rows:
		_shadowed(Vector2(at.x + 14, y), r[0], 9, DIM)
		_shadowed(Vector2(at.x - 14, y), r[1], 10, PALE, pw, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 18
	if game.new_best:
		_shadowed(Vector2(0, at.y + ph + 14), "a new best time", 9, WARM, vs.x, HORIZONTAL_ALIGNMENT_CENTER)

	var bw := 150.0
	var gap := 12.0
	var x0 := (vs.x - (bw * 2 + gap)) * 0.5
	_button(Rect2(Vector2(x0, 238), Vector2(bw, 28)), "play", "GO AGAIN", 12)
	_button(Rect2(Vector2(x0 + bw + gap, 238), Vector2(bw, 28)), "home", "MAIN MENU", 12)
